/* watchdog — run a command under a hard wall-clock cap and an idle/stall cap.
 *
 * The build pipeline runs under hellish, which is not yet fully stable: a phase
 * can deadlock or spin with no output. This guards every long step so a hung
 * process never wedges the host. Design goals: never hang itself, never kill
 * anything outside the child's own process group, lose no output.
 *
 * Mechanism (single-threaded, no concurrency hazards):
 *   - child runs in its own process group; we kill(-pgid) to take the whole tree.
 *   - child stdout+stderr are merged into one pipe we read; each read resets the
 *     idle timer, so "no output for IDLE seconds" is detected as a stall.
 *   - signals (SIGCHLD/SIGTERM/SIGINT/SIGHUP) are turned into bytes on a
 *     self-pipe via async-signal-safe handlers, and consumed by the poll() loop.
 *   - timeouts are computed as poll() deadlines (no SIGALRM races).
 * On a cap hit: SIGTERM the group, wait up to GRACE, then SIGKILL. Always reap.
 *
 * Usage: watchdog [-t total_s] [-i idle_s] [-k grace_s] [-v] -- cmd [args...]
 * Exit:  child's status; 124 total timeout; 125 idle stall; 126/127 spawn error;
 *        128+signo if the child died from a signal.
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>

#define WD_TOTAL 124
#define WD_IDLE 125
#define WD_SPAWN 126
#define WD_NOENT 127
#define BUFSZ 65536

enum reason { R_NORMAL = 0, R_TOTAL, R_IDLE, R_SIGNAL };

struct opts {
	long	total_ms;
	long	idle_ms;
	long	grace_ms;
	int	verbose;
	char	**cmd;
};

static int	g_selfpipe[2] = {-1, -1};

static long	mono_ms(void)
{
	struct timespec	ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (ts.tv_sec * 1000L + ts.tv_nsec / 1000000L);
}

static void	msleep(long ms)
{
	struct timespec	ts;

	ts.tv_sec = ms / 1000;
	ts.tv_nsec = (ms % 1000) * 1000000L;
	nanosleep(&ts, NULL);
}

static void	on_signal(int sig)
{
	unsigned char	c;
	int		saved;
	ssize_t		w;

	saved = errno;
	c = (unsigned char)sig;
	w = write(g_selfpipe[1], &c, 1);
	(void)w;
	errno = saved;
}

static void	die(const char *msg)
{
	fprintf(stderr, "watchdog: %s: %s\n", msg, strerror(errno));
	exit(WD_SPAWN);
}

static void	set_nonblock(int fd)
{
	int	fl;

	fl = fcntl(fd, F_GETFL, 0);
	if (fl >= 0)
		fcntl(fd, F_SETFL, fl | O_NONBLOCK);
}

static void	install_one(int sig)
{
	struct sigaction	sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_signal;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = SA_RESTART;
	if (sigaction(sig, &sa, NULL) < 0)
		die("sigaction");
}

static void	setup_signals(void)
{
	if (pipe(g_selfpipe) < 0)
		die("pipe(self)");
	set_nonblock(g_selfpipe[0]);
	install_one(SIGCHLD);
	install_one(SIGTERM);
	install_one(SIGINT);
	install_one(SIGHUP);
}

/* child side: own process group, merge stdout+stderr to the pipe, exec. */
static void	child_exec(char **cmd, int wpipe)
{
	setpgid(0, 0);
	if (dup2(wpipe, STDOUT_FILENO) < 0 || dup2(wpipe, STDERR_FILENO) < 0)
		_exit(WD_SPAWN);
	close(wpipe);
	close(g_selfpipe[0]);
	close(g_selfpipe[1]);
	execvp(cmd[0], cmd);
	if (errno == ENOENT)
		_exit(WD_NOENT);
	_exit(WD_SPAWN);
}

static pid_t	spawn(char **cmd, int *rfd)
{
	int	p[2];
	pid_t	pid;

	if (pipe(p) < 0)
		die("pipe(out)");
	pid = fork();
	if (pid < 0)
		die("fork");
	if (pid == 0)
	{
		close(p[0]);
		child_exec(cmd, p[1]);
	}
	setpgid(pid, pid);
	close(p[1]);
	set_nonblock(p[0]);
	*rfd = p[0];
	return (pid);
}

static int	exit_code(int status, enum reason why)
{
	if (why == R_TOTAL)
		return (WD_TOTAL);
	if (why == R_IDLE)
		return (WD_IDLE);
	if (WIFSIGNALED(status))
		return (128 + WTERMSIG(status));
	if (WIFEXITED(status))
		return (WEXITSTATUS(status));
	return (1);
}

/* forward one chunk of child output; returns 0 on EOF, 1 otherwise. */
static int	pump(int rfd)
{
	char	buf[BUFSZ];
	ssize_t	n;

	n = read(rfd, buf, sizeof(buf));
	if (n > 0)
	{
		(void)!write(STDOUT_FILENO, buf, (size_t)n);
		return (1);
	}
	if (n < 0 && (errno == EINTR || errno == EAGAIN))
		return (1);
	return (0);
}

/* drain remaining output after the child is gone, bounded so we never hang. */
static void	drain(int rfd)
{
	struct pollfd	pfd;
	long		deadline;

	deadline = mono_ms() + 2000;
	pfd.fd = rfd;
	pfd.events = POLLIN;
	while (mono_ms() < deadline)
	{
		if (poll(&pfd, 1, 200) <= 0)
			break ;
		if (!pump(rfd))
			break ;
	}
}

static void	kill_group(pid_t pid, long grace_ms)
{
	long	deadline;
	int	st;

	if (pid <= 1)
		return ;
	kill(-pid, SIGTERM);
	deadline = mono_ms() + grace_ms;
	while (mono_ms() < deadline)
	{
		if (waitpid(pid, &st, WNOHANG) == pid)
			return ;
		msleep(50);
	}
	kill(-pid, SIGKILL);
	waitpid(pid, &st, 0);
}

/* compute the next poll() timeout from the idle and total deadlines. */
static int	next_timeout(struct opts *o, long start, long last)
{
	long	now;
	long	t;
	long	cand;

	now = mono_ms();
	t = -1;
	if (o->idle_ms > 0)
	{
		cand = last + o->idle_ms - now;
		t = (cand < 0) ? 0 : cand;
	}
	if (o->total_ms > 0)
	{
		cand = start + o->total_ms - now;
		if (cand < 0)
			cand = 0;
		if (t < 0 || cand < t)
			t = cand;
	}
	if (t > 1000 || t < 0)
		t = (t < 0) ? 1000 : t;
	return ((int)t);
}

/* which cap (if any) has expired right now? */
static enum reason	expired(struct opts *o, long start, long last)
{
	long	now;

	now = mono_ms();
	if (o->total_ms > 0 && now - start >= o->total_ms)
		return (R_TOTAL);
	if (o->idle_ms > 0 && now - last >= o->idle_ms)
		return (R_IDLE);
	return (R_NORMAL);
}

struct loopst {
	pid_t		pid;
	int		rfd;
	int		eof;
	int		gone;
	int		status;
	enum reason	why;
};

/* consume signal bytes from the self-pipe; sets gone/why as needed. */
static void	handle_signals(struct loopst *s)
{
	unsigned char	buf[64];
	ssize_t		n;
	ssize_t		i;

	n = read(g_selfpipe[0], buf, sizeof(buf));
	i = 0;
	while (i < n)
	{
		if (buf[i] == SIGCHLD)
		{
			if (waitpid(s->pid, &s->status, WNOHANG) == s->pid)
				s->gone = 1;
		}
		else
		{
			if (s->why == R_NORMAL)
				s->why = R_SIGNAL;
			s->gone = -1;
		}
		i++;
	}
}

static int	run(struct opts *o, pid_t pid, int rfd)
{
	struct loopst	s = {pid, rfd, 0, 0, 0, R_NORMAL};
	struct pollfd	fds[2];
	long		start;
	long		last;
	int		n;

	start = mono_ms();
	last = start;
	while (!s.gone)
	{
		fds[0].fd = s.eof ? -1 : rfd;
		fds[0].events = POLLIN;
		fds[1].fd = g_selfpipe[0];
		fds[1].events = POLLIN;
		n = poll(fds, 2, next_timeout(o, start, last));
		if (n < 0 && errno != EINTR)
			break ;
		if (n == 0)
		{
			s.why = expired(o, start, last);
			if (s.why != R_NORMAL)
				break ;
			continue ;
		}
		if (!s.eof && (fds[0].revents & (POLLIN | POLLHUP)))
		{
			if (pump(rfd))
				last = mono_ms();
			else
				s.eof = 1;
		}
		if (fds[1].revents & POLLIN)
			handle_signals(&s);
	}
	if (s.gone != 1 && s.why == R_NORMAL && expired(o, start, last))
		s.why = expired(o, start, last);
	if (s.why == R_TOTAL || s.why == R_IDLE || s.why == R_SIGNAL)
	{
		if (o->verbose)
			fprintf(stderr, "watchdog: terminating (reason %d)\n", s.why);
		kill_group(pid, o->grace_ms);
	}
	if (s.gone != 1)
		waitpid(pid, &s.status, 0);
	drain(rfd);
	return (exit_code(s.status, s.why));
}

static long	parse_s(const char *a)
{
	char	*end;
	long	v;

	v = strtol(a, &end, 10);
	if (*end != '\0' || v < 0)
	{
		fprintf(stderr, "watchdog: bad number: %s\n", a);
		exit(WD_SPAWN);
	}
	return (v * 1000L);
}

static void	usage(void)
{
	fprintf(stderr,
		"usage: watchdog [-t total_s] [-i idle_s] [-k grace_s] [-v] -- cmd ...\n");
	exit(WD_SPAWN);
}

static int	parse_args(int ac, char **av, struct opts *o)
{
	int	i;

	o->total_ms = 0;
	o->idle_ms = 0;
	o->grace_ms = 10000;
	o->verbose = 0;
	i = 1;
	while (i < ac && av[i][0] == '-' && av[i][1] != '\0' && strcmp(av[i], "--"))
	{
		if (!strcmp(av[i], "-t") && i + 1 < ac)
			o->total_ms = parse_s(av[++i]);
		else if (!strcmp(av[i], "-i") && i + 1 < ac)
			o->idle_ms = parse_s(av[++i]);
		else if (!strcmp(av[i], "-k") && i + 1 < ac)
			o->grace_ms = parse_s(av[++i]);
		else if (!strcmp(av[i], "-v"))
			o->verbose = 1;
		else
			usage();
		i++;
	}
	if (i < ac && !strcmp(av[i], "--"))
		i++;
	return (i);
}

int	main(int ac, char **av)
{
	struct opts	o;
	pid_t		pid;
	int		rfd;
	int		i;

	i = parse_args(ac, av, &o);
	if (i >= ac)
		usage();
	o.cmd = &av[i];
	setvbuf(stdout, NULL, _IONBF, 0);
	setup_signals();
	pid = spawn(o.cmd, &rfd);
	return (run(&o, pid, rfd));
}
