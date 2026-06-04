#!/bin/sh
# Functional tests for the watchdog. Run inside the builder container:
#   docker compose run --rm builder sh /project/tools/watchdog/test.sh
# Every case is itself bounded, so this harness can never hang.
WD="${WD:-/output/bin/watchdog}"
fail=0
ok() { printf 'ok   %s\n' "$1"; }
ko() {
	printf 'FAIL %s -- %s\n' "$1" "$2"
	fail=$((fail + 1))
}

[ -x "$WD" ] || {
	echo "watchdog binary not found/executable at $WD"
	exit 2
}

# 1 — normal exit + output forwarded
out=$("$WD" -t 10 -- sh -c 'echo hi')
rc=$?
{ [ "$rc" = 0 ] && [ "$out" = hi ]; } && ok "normal" || ko "normal" "rc=$rc out=[$out]"

# 2 — child exit code propagated verbatim
"$WD" -t 10 -- sh -c 'exit 7'
[ $? = 7 ] && ok "exit-code" || ko "exit-code" "rc=$?"

# 3 — child killed by signal -> 128+signo (SIGKILL=9 -> 137)
"$WD" -t 10 -- sh -c 'kill -9 $$'
[ $? = 137 ] && ok "signal-map" || ko "signal-map" "rc=$?"

# 4 — total timeout fires and is bounded
s=$(date +%s)
"$WD" -t 1 -k 1 -- sh -c 'sleep 30'
rc=$?
e=$(($(date +%s) - s))
{ [ "$rc" = 124 ] && [ "$e" -le 5 ]; } && ok "total-timeout" || ko "total-timeout" "rc=$rc e=${e}s"

# 5 — idle/stall timeout fires (output then silence)
s=$(date +%s)
"$WD" -i 1 -k 1 -- sh -c 'echo go; sleep 30'
rc=$?
e=$(($(date +%s) - s))
{ [ "$rc" = 125 ] && [ "$e" -le 5 ]; } && ok "idle-timeout" || ko "idle-timeout" "rc=$rc e=${e}s"

# 6 — steady output must NOT trip the idle cap
"$WD" -i 2 -- sh -c 'i=0; while [ $i -lt 4 ]; do echo $i; sleep 1; i=$((i+1)); done'
[ $? = 0 ] && ok "idle-reset" || ko "idle-reset" "rc=$?"

# 7 — whole process group is taken down (no surviving grandchild)
"$WD" -t 1 -k 1 -- sh -c 'sleep 47 & sleep 47'
sleep 1
if pgrep -f 'sleep 47' >/dev/null 2>&1; then
	ko "pgroup-kill" "orphan sleep survived"
	pkill -9 -f 'sleep 47' 2>/dev/null
else
	ok "pgroup-kill"
fi

# 8 — no output is lost under load
n=$("$WD" -t 30 -- sh -c 'seq 1 100000' | wc -l | tr -d ' ')
[ "$n" = 100000 ] && ok "output-integrity" || ko "output-integrity" "lines=$n"

# 9 — watchdog itself leaves no zombie of its child
z=$(ps -eo stat= 2>/dev/null | grep -c Z)
[ "${z:-0}" -eq 0 ] && ok "no-zombies" || ko "no-zombies" "zombies=$z"

echo "==> watchdog: $fail failure(s)"
[ "$fail" = 0 ]
