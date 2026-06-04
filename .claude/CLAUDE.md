# ft_linux — how_to_train_your_kernel

## Project

42 school project: build a complete Linux distribution from source (LFS-style).
Subject version 3.6. Student login: **dlesieur**.

**Goals:**
- Build a Linux kernel >= 4.0 (we target 6.6 LTS)
- Build and install all mandatory packages from source
- FHS-compliant filesystem hierarchy
- Internet connectivity in the final system

**Submission:** push a `shasum` of the disk image, not the image itself.
Run `make shasum` to generate `build/disk.sha256`.

---

## Hard Rule: Zero Host Pollution

The host machine must remain untouched. The user has been explicit about this.

- **All compilation runs inside Docker.** Never `apt install` build tools on the host.
- **The only host deps are `docker` and `qemu-system-x86_64`.** Check with `make deps`.
- **Disk image lives in `./build/`** which is gitignored. Nothing leaks outside the project dir.
- The legacy `scripts/install_deps.sh` is for evaluators who choose the host-install route.
  We do **not** run it on the dev machine — it's kept only as reference.

If you ever need a build tool you don't have, add it to `docker/Dockerfile`,
not to the host.

---

## Hard Rule: hellish runs every build script (the other big one)

Every phase script runs under **hellish** — the user's own shell (a 42sh),
vendored at `vendor/42sh` (submodule → `Univers42/42sh`), **never bash**. This is
"pure hellish": no bash fallback in the real build.

- The Makefile sets `RUNNER := hellish`; each phase runs
  `$(COMPOSE) run --rm builder $(RUNNER) /project/scripts/0X.sh`. `RUNNER=bash` is
  a **debug-only** override (e.g. to A/B a failing phase).
- hellish is **baked into the builder image**: `docker/Dockerfile` is multi-stage —
  `ARG HELLISH_IMAGE=dlesieur/hellish-shell:<tag>`, `FROM ${HELLISH_IMAGE} AS hellish`,
  then `COPY --from=hellish /usr/local/bin/hellish`. That image is built from
  `vendor/42sh` (its own `vendor/42sh/Dockerfile` packages the binary) and pushed to
  **Docker Hub** (`dlesieur/hellish-shell:latest` + per-commit tags). Creds are in
  `vendor/42sh/.env` (`DOCKER_LOGIN`, `DOCKER_PAS`; **gitignored** — never commit;
  use `--password-stdin`).
- **When hellish can't run a script, fix hellish, not the script** — *unless* the
  script also fails under bash (then it's a genuine script bug, fix the script).
  See "Fixing hellish" below. Scripts are mounted read-only from `/project`, so a
  script edit is live immediately; a hellish change needs the image rebuilt.

hellish is the BUILD-script interpreter in the builder container. The FINAL LFS image
still ships **bash** (a mandatory package built from source) — different shells.

---

## Architecture

```
ft_linux/
├── docker/                ← build environment (Debian 12 + LFS toolchain prereqs)
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── entrypoint.sh
├── scripts/               ← LFS build phases, run inside the container
│   ├── lib.sh             ← shared helpers, constants, logging, loop/stamp utils
│   ├── packages.sh        ← pinned package versions + download URLs
│   ├── build-toolchain-lib.sh ← build_* functions for the Ch.5-6 toolchain
│   ├── 00-init-disk.sh    ← create + partition + format the 20 GB image
│   ├── 01-build-toolchain.sh ← LFS ch. 5-6: cross-toolchain (IMPLEMENTED)
│   ├── 02-build-system.sh    ← LFS ch. 8: chroot package build (STUB — see below)
│   ├── 03-build-kernel.sh    ← LFS ch. 10: kernel 6.6.32 with -dlesieur suffix
│   ├── 04-configure-system.sh ← LFS ch. 9-11: hostname, fstab, network, GRUB
│   ├── install_deps.sh    ← legacy host-install (reference only, never run here)
│   ├── check-hellish.sh   ← per-script differential: hellish vs bash (make check-hellish)
│   ├── conformance.sh     ← construct gate: every shell feature the scripts use, hellish vs bash
│   └── vm-run.sh          ← QEMU launcher (runs on the host)
├── vendor/42sh/           ← submodule: hellish (our 42sh shell). Built → Docker Hub.
│   └── tests/regress_hellish ← regression cases for every hellish fix (make test)
├── build/                 ← gitignored: everything the build produces
│   ├── ft_linux.img       ← 20 GB raw — the deliverable AND the live LFS tree
│   ├── disk.sha256        ← submission artifact
│   ├── sources/           ← cached source tarballs (idempotent re-runs)
│   └── logs/              ← per-phase build logs
├── docs/                  ← empty; the subject PDF now lives at scripts/en.subject.pdf
└── Makefile               ← single entry point for everything

Note: configs/kernel/.config is referenced by 03-build-kernel.sh but does NOT
exist yet — see "Current Build State" below.
```

---

## Workflow

```bash
make deps         # verify host has docker + qemu, nothing else
make image        # build the Docker build environment
make build        # full LFS build: disk → toolchain → packages → kernel → config
make run          # boot build/ft_linux.img in QEMU
make shell        # interactive shell in the build container
make shasum       # generate build/disk.sha256 for submission
make clean        # nuke build/ (the disk image and logs)

# Phases individually (each is re-entrant); all run under hellish (RUNNER):
make phase-disk
make phase-toolchain
make phase-packages
make phase-kernel
make phase-system
make phase-toolchain RUNNER=bash   # debug-only: A/B a phase under bash

# Host-side quality (host already has shellcheck/shfmt/hellish — no installs):
make lint            # shellcheck -x + shfmt -d over scripts/
make fmt             # shfmt -w (apply formatting)
make check-hellish   # run scripts/ under hellish vs bash, report divergences
HELLISH=vendor/42sh/build/bin/hellish bash scripts/conformance.sh  # construct gate

# Inside vendor/42sh (the hellish shell): build + its own gates
make -C vendor/42sh         # debug+ASan build → build/bin/hellish
make -C vendor/42sh test    # full functional suite (incl. regress_hellish)
make -C vendor/42sh bench   # speed vs `bash --posix` (geomean must stay ≥ ~1.0)
make -C vendor/42sh norm    # norminette
```

---

## Current Build State (what's real vs. stubbed)

Do **not** assume `make build` yields a bootable system — re-verify against the
scripts, but as it stands:

- **Phase 0 `00-init-disk.sh` — done; runs end-to-end under hellish** (validated:
  20 GB GPT image, 4 partitions, ext4 + swap).
- **Phase 1 `01-build-toolchain.sh` — builds under bash; being brought up under hellish.**
  Ch.5 cross-toolchain + Ch.6 temp tools (~17 pkgs); logic in `build-toolchain-lib.sh`,
  versions in `packages.sh`. Under `RUNNER=bash` it builds (binutils → gcc-pass1 …). Under
  hellish it now clears skeleton/fetch/extract and reaches **binutils `configure`**; the
  current frontier is an autotools build-type detection failure there (use the bash run as
  the oracle — it passes — to isolate the remaining hellish gap). Two **script** bugs were
  fixed along the way (they broke bash too): `info()` wrote to stdout and polluted
  `fetch()`'s command-substituted return; `extract()` used a fragile before/after `ls`
  diff — now derives the dir from the tarball and is idempotent.
- **Phase 2 `02-build-system.sh` — STUB.** It only prints LFS Ch.8 guidance and exits.
  The 80+ mandatory packages are NOT built, and `packages.sh` does not yet pin their
  versions. **This is the main unfinished subject work** (mirror the toolchain pattern:
  new `scripts/build-system-lib.sh` of `build_<pkg>()` fns + `packages.sh` entries, driven
  by `02-build-system.sh` in a chroot).
- **Phase 3 `03-build-kernel.sh` — done, but** it reads `configs/kernel/.config`, which
  doesn't exist, so it falls back to `make defconfig` (not tuned for QEMU virtio). After
  a build it writes `build/kernel.config.saved`; commit a curated copy to
  `configs/kernel/.config` for reproducible, bootable kernels.
- **Phase 4 `04-configure-system.sh` — done.** hostname, fstab (by LABEL), network stub,
  inittab, BIOS GRUB on the GPT bios_grub partition, passwordless root.

Consequence: with Phase 2 stubbed, a full `make build` produces an image with a
toolchain + kernel but no real userland. Implementing Phase 2 is the priority before
the image can boot to a usable system.

---

## Implementation Notes (non-obvious, learned from reading the scripts)

- **Partition layout (GPT, 4 parts):** p1 `bios_grub` (~2 MB, GRUB core), p2 `/boot`
  ext4, p3 swap, p4 `/` ext4. Scripts mount **p4 as root, p2 as boot** — mind the
  off-by-one (p1 is the BIOS-boot stub). Still satisfies the subject's "≥3 partitions".
- **Loop devices use kpartx, not `losetup --partscan`.** Docker has no udev, so partition
  nodes only appear under `/dev/mapper/loopXpN`. Always use the `attach_image` /
  `part "$LOOP" N` / `detach_image` helpers in `lib.sh`, never raw `losetup`.
- **Phase 1 is re-entrant via stamps.** `step <name> <fn>` skips work when
  `$LFS/.stamps/<name>` exists. To force one step to rebuild, delete its stamp file
  inside the mounted image and re-run `make phase-toolchain`.
- **Source tarballs are cached** in `build/sources` (`/output/sources`) by `fetch()`;
  re-runs don't redownload. Versions/URLs are pinned in `scripts/packages.sh`.
- **Subject constants are duplicated** across `Makefile`, `docker/docker-compose.yml`
  (env), `scripts/lib.sh`, and `docker/entrypoint.sh`. Bump `KERNEL_VERSION` /
  `STUDENT_LOGIN` in all of them together.
- **GRUB is legacy BIOS** (`grub-install --target=i386-pc`), not UEFI; `vm-run.sh` boots
  the raw image with `-boot c` and virtio disk/net.

---

## Subject Constraints (verify on every change)

| Constraint | Value |
|---|---|
| Kernel version | >= 4.0 — we use **6.6.32 LTS** |
| `uname -r` output | `6.6.32-dlesieur` |
| Kernel binary | `/boot/vmlinuz-6.6.32-dlesieur` |
| Kernel sources path | `/usr/src/kernel-6.6.32` |
| Hostname | `dlesieur` |
| Partitions | >= 3: `/boot`, swap, `/` |
| Module loader | **eudev** |
| Init system | SysVinit (simpler than systemd) |
| Bootloader | GRUB 2 |
| Network | `curl` or `wget` must work in final system |
| Package mgmt | must be possible to install new packages on final system |

---

## Mandatory Packages

Acl, Attr, Autoconf, Automake, Bash, Bc, Binutils, Bison, Bzip2, Check,
Coreutils, DejaGNU, Diffutils, Eudev, E2fsprogs, Expat, Expect, File,
Findutils, Flex, Gawk, GCC, GDBM, Gettext, Glibc, GMP, Gperf, Grep, Groff,
GRUB, Gzip, Iana-Etc, Inetutils, Intltool, IPRoute2, Kbd, Kmod, Less, Libcap,
Libpipeline, Libtool, M4, Make, Man-DB, Man-pages, MPC, MPFR, Ncurses, Patch,
Perl, Pkg-config, Procps, Psmisc, Readline, Sed, Shadow, Sysklogd, Sysvinit,
Tar, Tcl, Texinfo, Time Zone Data, Udev-lfs Tarball, Util-linux, Vim,
XML::Parser, Xz Utils, Zlib.

Source-of-truth list: LFS book v12.x stable.
Reference: https://www.linuxfromscratch.org/lfs/view/stable/

---

## Docker Container Strategy

- Base: `debian:12-slim`. **Multi-stage:** an `ARG HELLISH_IMAGE` stage provides the
  hellish binary, `COPY`'d to `/usr/local/bin/hellish` in the final stage (which also adds
  `libreadline8`/`libtinfo6`, hellish's runtime deps). The hellish binary needs only
  `GLIBC_2.34`, so the ubuntu-built image is compatible with the debian:12 builder.
- Installs LFS host requirements (gcc, make, bison, gawk, texinfo, etc.) — see Dockerfile
- Runs `--privileged` only for loop device + chroot (no kernel modules touched)
- Mounts (see `docker/docker-compose.yml`):
  - `..:/project:ro` — source tree (read-only)
  - `../build:/output` — disk image, source cache, and logs (read-write)
- **No named volume.** `/mnt/lfs` is just an empty dir inside the (ephemeral,
  `--rm`) container; each phase re-mounts the disk image's root partition over it
  from the loop device. The persistent LFS tree therefore lives **inside
  `build/ft_linux.img`**, not in Docker. A named volume there would collide with
  that mount — which is why compose deliberately omits one.

The container writes **only** to `./build/`. To start clean, `make clean`
(removes `build/`); there is no docker volume to wipe.

---

## Fixing hellish (the iterate-fix loop)

> Full runbook + Definition-of-Done checklist: **`.claude/hellish-workflow.md`**.

The point of running the build under hellish is to harden hellish. When a script
fails under hellish (and works under bash), it's a hellish bug to fix in `vendor/42sh`.

**Per-bug loop:** branch in `vendor/42sh` (work branch is `repair/full-green`, not
`main`) → reproduce (`make -C vendor/42sh`, then `build/bin/hellish -c '<repro>'`;
debug build is ASan) → root-cause fix in `src/…` (norminette-clean) → add a case to
`tests/regress_hellish` → gates: `make -C vendor/42sh test` (full suite, ~1703) +
`bench` (geomean vs `bash --posix` must stay ≥ ~1.0; wall-clock faster) + `norm` →
commit **as sole author, NO `Co-Authored-By` trailer** (this overrides the default,
for both `vendor/42sh` and ft_linux superproject commits) → rebuild + republish the
hellish image → rebuild the builder → re-run the phase. Pushing to `Univers42/*` and
`make my_shell` (sudo) are user-gated.

**Gates that must stay green after any hellish change:** the **1742** functional tests,
`norm`, and the benchmark geomean (OVERALL ≥ ~1.0; currently 1.008x, wall 1.211x faster —
perf: libft must be built `-O3`; its default Makefile shipped `-O0`, slower than bash).

**hellish fixes already landed** (each with a `regress_hellish` case): assignment-only
command crash (NULL `argv`), bare-`for` crash, `source`/`eval` leading-comment, `exec >
>(tee)` hang (don't block-wait exec-bound procsubs), `pushd`/`popd` builtins, `set -o
pipefail`, `[[ … ]]` single-test, brace expansion with a `$var`/quoted prefix, process
substitution inheriting non-exported shell vars (`get_envp_all`), **line-continuation in
sourced files** (tokenizer `skip_noise`), **consecutive heredocs** (`extract2` advance_hd),
**heredoc-body-quote desync in sourced strings** (`extract3` line-by-line collect), and
**braced `${VAR}` in unquoted heredoc bodies** (`helpers3` `expand_braced`).

**Known hellish gaps — ALL verified host-bash-only, NOT hit by the hellish-run build:**
- `[[ a == a ]]` (double-equals) returns false; only `[[ a = a ]]` works. (conformance.sh,
  check-hellish.sh — host/bash.)
- `[[ … && … ]]` / `[[ … || … ]]` internal logic — splits on `&&`. (vm-run.sh, host/bash.)
  A 2026-06-04 fix attempt **infinite-looped** on `&&`/`||`; a retry needs loop-safe
  short-circuit eval with correct `!`/`( )`/`||`<`&&` precedence.
- `set -e` doesn't abort a failing *multi-stage pipeline* (simple cmds do).
- script-FILE (non-sourced) heredoc with a leading-quote body line (sourced path is fixed).
- word-path malformed brace `echo "${FOO"` → `ft_assert` crash (reparse_dquote.c) on bad input.
- arrays `a=(…)` (only `vm-run.sh`, host/bash).
Each is hellish-completeness hardening; add a `regress_hellish` + `conformance.sh` case as fixed.

**The conformance gate (`scripts/conformance.sh`) must be green before any long build.**
It diffs every construct the scripts use (sourcing/comments, heredocs, procsub, `exec >
>()`, `[[ ]]`, brace-with-var, pipefail, pushd/popd, traps, `set -euo pipefail`, …)
under hellish vs bash — that's what catches a gap *before* a 30–60 min phase deadlocks.

---

## What Claude Should Help With

- Debug individual build phase scripts (gcc build failures, missing deps, configure flags)
- Tune the kernel `.config` for QEMU virtio
- GRUB configuration for the disk image
- SysVinit boot scripts (network, syslog, agetty)
- Network configuration (DHCP via inetutils or static)
- Implement Phase 2 (Ch.8) and harden hellish against the constructs it uses
- Generate the shasum for submission

## What Claude Must NOT Do

- Run `sudo apt install`, `pip install`, or any host package installer
- Modify anything outside `/home/dlesieur/Documents/ft_linux/`
- Commit `build/ft_linux.img` (20 GB) or anything from `build/`; never commit `.env`
- Run kernel builds outside the container
- Suggest "just install X on the host" as a workaround — always fix in Dockerfile
- Add a `Co-Authored-By` trailer to commits (user is sole author here)
- "Work around" a hellish bug by rewriting a script to avoid the construct — fix hellish
  (unless the script also fails under bash, i.e. it's a real script bug). Use the
  `RUNNER=bash` run as the oracle for what correct behavior is.

If a build fails, the answer is **never** to install something on the host.