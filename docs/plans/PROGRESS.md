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
