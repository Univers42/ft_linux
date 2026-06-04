# PROGRESS — ft_linux autonomous run log

Append-only, newest at top. One entry per milestone or significant decision. This + the
git log on `develop` + `$LFS/.stamps/` + `build/logs/` are the source of truth for
resuming. Format per entry:

```
## YYYY-MM-DD HH:MM — <milestone/topic>
- did: …
- result: … (tests/conformance/build status)
- decided: … (+ why)
- next: …
```

---

## 2026-06-04 — M2: full Ch.8 wiring done; B1 build launched under hellish-in-chroot
- did: heredoc fix landed (vendor/42sh 09f6f41, 1738 tests) + image republished (both
  hellish fixes). Ch.8 recipes regenerated for LFS 12.1 (build-system-lib.sh, 26 build_*
  fns reusing toolchain version vars; packages.sh Ch.8 + MD5 + CH8_SOURCES). Wrote the
  in-chroot driver: chroot-lib.sh (unpack/fetch resolve PRE-STAGED /sources tarballs — no
  network; watchdog guard; -j heuristic) + build-all.sh (per-pkg guarded hellish, stamped,
  order derived from build-system-lib.sh). 02-build-system.sh: prefetch CH8_SOURCES into the
  image's /sources, stage hellish+libs+watchdog+scripts, smoke-test hellish-in-chroot, run
  build-all. Verified heredoc fix unblocked write_etc_files; fixed a `set -e && ` pitfall.
- commits: c54d0d7 (recipes+bump), e51c95b (driver), plus chroot-lib/build-all/prefetch.
- result: **`make phase-packages` launched (background)** — prefetch (~1GB) → hellish-in-
  chroot smoke → build B1 (man-pages..gcc, ~25 pkgs). Long (glibc+gcc ~20min each). Each
  package guarded (idle 30m/total 3h) + stamped (re-entrant via /sources/.stamps).
- watch for: recipe bugs (LFS 12.1 exactness), more hellish gaps surfacing in recipes
  (heredocs/continuations now fixed), gcc test suite needing a `tester` user (test is
  non-fatal `|| true`, so likely OK; add tester after shadow if it errors), disk space
  (40GB host; image 20GB — monitor). Fix per failure (script bug → fix script; hellish
  divergence vs bash → fix hellish per .claude/hellish-workflow.md), re-run (stamps resume).
- next: B1 green → B2/B3 recipes (agent) → strip/cleanup → M7 (kernel/boot/net/shasum).

## 2026-06-04 — M2 in progress: chroot driver done; heredoc bug + Ch.8 recipes underway
- did: rewrote `scripts/02-build-system.sh` (commit e51c95b) — real LFS Ch.7 chroot prep
  (virtual FS, dir skeleton, /etc/{passwd,group,hosts}, /dev nodes), **stages hellish +
  libreadline.so.8/libtinfo.so.6 + the static watchdog + the build scripts into the
  chroot** (so the in-chroot build runs under hellish too), then a hellish-in-chroot smoke
  test, then `/sources/scripts/build-all.sh` if present. CHROOT_ENV uses LD_LIBRARY_PATH=
  /tools/lib for hellish's libs.
- BLOCKER (hellish bug, reproduced): **consecutive heredocs** — the 2nd `cat <<"E2"` in a
  function isn't found ("here-document delimited by EOF (wanted E2)"); body leaks as
  commands. bash is fine. Hit it in 02's write_etc_files. Heredocs are everywhere
  (04-configure, recipes) so it's blocking. **Background agent fixing it** in vendor/42sh
  (full DoD: 1735 tests + bench + norm + regress + merge develop). Reproducer:
  a function with two `cat <<"EOF" … EOF` blocks.
- Ch.8 recipes: a first agent drafted `build-system-lib.sh` + packages.sh Ch.8 but targeted
  LFS **12.4** (gcc 15.2/glibc 2.42) — WRONG; our toolchain is LFS **12.1** (gcc 13.2.0/
  glibc 2.39/binutils 2.42, already pinned in packages.sh lines 1-74). **Re-tasked a
  background agent** to regenerate against LFS 12.1, REUSING the toolchain version vars,
  using LFS MD5 (sha256 not published). The 12.4 draft on disk will be overwritten.
- next (when agents land): review heredoc fix → republish hellish image + rebuild builder →
  review/integrate 12.1 recipes → write `scripts/build-all.sh` (sources packages.sh +
  build-system-lib.sh, runs `step <pkg> build_<pkg>` over an ORDER list, guarded per pkg) +
  pre-fetch Ch.8 tarballs into $LFS/sources → `make phase-packages` (smoke + B1 build).
  Also: create a `tester` user in the chroot before build_gcc (its test suite needs it).

## 2026-06-04 — M1 COMPLETE: full cross-toolchain built end-to-end under hellish
- did: fixed two more pre-existing **script** bugs (never hit before — toolchain never
  completed under any shell): `build_ncurses`/`build_file` built a host tool (tic/file) in
  `$src/build`, then `with_clean_build` wiped that dir → `TIC_PATH`/`FILE_COMPILE` pointed
  at a nonexistent `build/build/...` (`tic: not found`). Fixed: cross-configure in `$src`
  (not a wiped subdir) per LFS; added ncurses `--enable-widec`. Re-ran phase-toolchain.
- result: **`PHASE DONE: 01-build-toolchain`**. 22 stamps (Ch.5 binutils-pass1, gcc-pass1,
  linux-headers, glibc, libstdcxx + all 17 Ch.6 pkgs incl. binutils-pass2, gcc-pass2).
  cross-gcc compiles+links a hello world (interp /lib64/ld-linux-x86-64.so.2). Commits
  d57b75d (limits.h), b32a94f (ncurses/file). Loops cleaned via `make loopclean`.
- decided: nothing new; the iterate-fix loop (run → hit a bug → fix script/hellish → re-run,
  stamps make it incremental) is working well.
- next: **M2 — LFS Ch.8 userland** (the main remaining subject work). Plan (docs/plans/02):
  (1) `02-build-system.sh`: pre-chroot skeleton (/dev nodes, /etc/{passwd,group,hosts},
  dir tree), **stage a script-mode hellish into `$LFS/tools/bin/hellish`** (+ run a chroot
  smoke test), enter chroot running a generated `build-all` under hellish (fallback: chroot
  bash per-package, logged). (2) `scripts/build-system-lib.sh`: `build_<pkg>()` recipes
  mirroring build-toolchain-lib.sh, **guarded by the watchdog per package**. (3) extend
  `packages.sh` with Ch.8 versions+URLs(+sha256). Order = LFS Ch.8 (B0 data → B1 core
  toolchain rebuild → B2 libs/utils → B3 system/eudev/sysvinit/grub → B4 strip). Watch for:
  more `\`-continuation-in-sourced-fn` (now handled), and chroot-specific hellish gaps
  (PATH, $(...), here-docs) — add conformance/regress cases for each.

## 2026-06-04 — M1: Ch.5 toolchain builds under hellish; fixed Ch.6 m4 (limits.h path)
- did: re-ran phase-toolchain under the fixed hellish. **Ch.5 fully built** (binutils-pass1,
  gcc-pass1, linux-headers, glibc, libstdc++) — the line-continuation fix worked end-to-end
  (gcc-pass1 configure now detects build type). Hit Ch.6 **m4**: `bits/stdlib.h "Assumed
  value of MB_LEN_MAX wrong"`. Root cause: the gcc-pass1 limits.h trick wrote to
  `…/install-tools/include/limits.h` but gcc searches `…/include/limits.h` (LFS book path) →
  gcc used its stock limits.h. **Script bug** (fails under bash too). Fixed
  `build-toolchain-lib.sh` (→ `include/limits.h`); verified m4 `c-stack.o` then compiles.
- result: committed d57b75d. Re-running phase-toolchain (gcc-pass1 stamped/skipped, m4+
  rebuild). Loop devices leaked by manual diagnostic mounts were cleared via `make loopclean`.
- decided: corrected the image's `include/limits.h` in place so the resume skips the 20-min
  gcc-pass1 rebuild; the script fix keeps clean `make build` reproducible.
- next: confirm toolchain completes (Ch.6 ~15 pkgs + binutils/gcc pass2), then M2 (Ch.8).

## 2026-06-04 — M0 done: watchdog + the toolchain blocker (line continuation)
- did: (M0a) wrote/tested C watchdog (`tools/watchdog`, 9/9): total + idle/stall
  timeouts, whole-pgroup kill; wired into Makefile phases (host `timeout` backstop +
  in-container watchdog) + `lib.sh guard()` + `make loopclean`; signal-safe teardown
  (`arm_cleanup`, since hellish doesn't run EXIT traps on SIGTERM). (M0b) extended
  `conformance.sh`. (M0c) **root-caused the toolchain blocker**: a `\<newline>` line
  continuation in a *sourced* function body (e.g. build_gcc_pass1) was lexed into a
  spurious word → word-splitting made it an empty/newline arg → `../configure` got `\n`
  args → autotools saw build_alias/host_alias with newlines ("config.sub: missing
  argument"). The REPL never hit it (it joins continuation lines first); exec_string
  (source/eval/command) feeds the whole string to the tokenizer. Fixed in
  `vendor/42sh` lexer (`tokenizer.c skip_noise`: skip `\<NL>` at token boundaries,
  quote/comment-safe). 
- result: hellish DoD GREEN — 1735 tests pass, norm clean, bench geomean 1.004x (wall
  1.206x faster, hard tests 1.041x, no MISMATCH). Merged to `vendor/42sh` develop
  (800dd4e). Conformance vs rebuilt builder: only `dbracket-logic` diverges (not used by
  the in-container build). Republished hellish OPT image locally + rebuilt builder.
- decided: defer `[[ && ]]` (dbracket-logic) and a pre-existing **ASan-debug-only**
  multi-line-script-FILE crash (baked OPT is clean; the real build uses OPT) to a
  hardening pass — neither blocks the subject. Diagnosis discipline: reproduce in the
  real sourced context, not hand-typed (hand-typed copies were misleadingly clean).
- next: phase-toolchain re-running under the fixed hellish (M1); then Ch.8 (M2+).

---

## 2026-06-04 — Planning complete (pre-journey)
- did: wrote the plan set under `docs/plans/` (00 master, 01 architecture/DSA, 02 Ch.8
  manifest, 03 hellish, 04 kernel/boot/net, 05 autonomy) + this log. Master strategy in
  `.claude/plans/snuggly-soaring-hanrahan.md`; hellish DoD in `.claude/hellish-workflow.md`.
- result: docs only; no code/build changes yet. Awaiting user go-ahead to start the journey.
- decided: hellish-in-chroot with per-package bash fallback; no cross-package parallelism +
  runtime-tuned `-j`; static network to QEMU user-net defaults; ship `wget` for the network
  requirement; practical (not bit-identical) reproducibility; no ccache. (See 01/04 for why.)
- open items found while planning: `MAKEFLAGS: "-j$(nproc)"` literal in docker-compose
  (compose won't expand `$()`); `conformance.sh` lacks an `exec > >(tee)` case; binutils
  `configure` fails under hellish only (frontier — see 03).
- next: on go-ahead, start **M0** (conformance cases + MAKEFLAGS fix + binutils-configure
  root-cause/fix + republish image), then M1.
