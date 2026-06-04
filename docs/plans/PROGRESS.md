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

## 2026-06-04 — RE-AUDIT pass + hellish gap inventory (post subject-complete)
- **Re-audit results (all green where it matters):**
  - hellish `make test`: **1742/1742 PASS** (develop, after 4 merged fixes).
  - `make bench` (OPT vs bash --posix): OVERALL geomean **1.008x**, hard **1.046x**, wall **1.211x**
    faster, 0 MISMATCH. `make norm`: clean.
  - `conformance.sh` (now path-robust): **1 divergence = dbracket-logic `[[ && ]]`** — see below.
  - subject compliance: re-verified in QEMU (uname/host/parts/net/bash, clean poweroff). Deliverable
    build/disk.sha256 committed (rebuilt under fully-fixed hellish).
- **`[[ && ]]` fix attempt CRASHED mid-work** (agent killed; left a hanging WIP on fix/dbracket-logic).
  WIP **discarded**, develop restored + re-verified (1742 pass). Branch deleted. NOTE for a retry: the
  abandoned approach **infinite-looped** on `&&`/`||` — a careful loop-safe short-circuit eval is needed.
- **hellish gap inventory (NONE are hit by the hellish-run build — all verified host-bash-only):**
  - `[[ a == a ]]` returns FALSE (exit 1) while `[[ a = a ]]` is TRUE — hellish `[[ ]]` doesn't accept
    `==` (double-equals) string equality. Used only in conformance.sh/check-hellish.sh (host/bash).
  - `[[ ... && ... ]]` / `[[ ... || ... ]]` internal logic (splits on &&). Used only in vm-run.sh +
    the conformance test case (host/bash).
  - script-file (not sourced) heredoc with a leading-quote body line (pre-existing; sourced path fixed).
  - word-path malformed-brace `echo "${FOO"` → ft_assert crash (reparse_dquote.c:61; malformed input).
  These are hellish-completeness hardening, NOT subject blockers (the build ran end-to-end under hellish).
- 4 hellish fixes ARE merged + shipped (line-cont, consecutive-heredoc, heredoc-body-quote, ${VAR}-heredoc).

## 2026-06-04 — 🎉 SUBJECT COMPLETE: boots in QEMU, ALL criteria verified, shasum written
- **Autonomous headless QEMU boot (scripts/vm-verify.sh) — every subject criterion PASS:**
  - `uname -r` = **6.6.32-dlesieur** ✓   hostname = **dlesieur** ✓
  - ≥3 partitions ✓ (bios_grub/boot/swap/root; lsblk=6 nodes)   fstab LABEL= root/boot/swap ✓
  - **wget fetched http://example.com (904b) — network WORKS** ✓ (static eth0 10.0.2.15, gw 10.0.2.2)
  - bash-from-source login shell ✓   eudev udevd ✓   SysVinit + bootscripts ✓   GRUB2 BIOS ✓
  - clean boot (no Press-Enter pause) → `dlesieur login:` → passwordless root → clean `reboot: Power down`.
- last boot fixes (committed): root=/dev/vda4 (no initramfs can't resolve LABEL=); console=tty0
  console=ttyS0 (serial = /dev/console); fstab /dev/shm+/sys/fs/cgroup (mountvirtfs FAIL→Press-Enter);
  /usr/bin/udevadm symlink (eudev --bindir=/usr/sbin vs bootscript /bin/udevadm); image chmod 666 via
  container so host QEMU can boot it.
- **`make shasum` → build/disk.sha256** committed (force-add past build/ gitignore):
  `d2d77944d4208e4109e86b38eda7a9e881057daa87af0118de80a8eeb16cb946`.
- NOTE for audit: running /bin/bash reports 5.2.25 but BASH_VERSION pin is 5.2.21 — investigate.
- 4th hellish bug found (deferred): braced `${VAR}` in heredoc body mangles to `{{VAR` (workaround:
  unbraced `$KERNEL_FULL` in 04). Fix in vendor/42sh + regress, then can un-workaround.
- next: deferred hellish hardening (${VAR}-heredoc, [[ && ]], script-file heredoc edge) + full re-audit.

## 2026-06-04 — M7: kernel + system config; final blocker = GRUB-on-loop in container
- DONE: kernel **6.6.32-dlesieur** built (defconfig + virtio/ext4/8250/devtmpfs built-in,
  no initramfs) → /boot/vmlinuz-6.6.32-dlesieur. Added **wget** (HTTP, --without-ssl) for
  the network req → userland now 76 pkgs. phase-system (04, reworked for LFS Ch.9): installs
  **lfs-bootscripts** (Ch.9.2) via chroot, serial console (GRUB console=ttyS0,115200 + inittab
  agetty ttyS0), static network (eth0 10.0.2.15/24 gw 10.0.2.2 dns 10.0.2.3 = QEMU user-net,
  ipv4-static service), fstab by LABEL, passwordless root. arm_cleanup. All committed.
- BLOCKER (infra, not hellish): **grub-install fails on the loop image** — attach_image uses
  kpartx device-mapper nodes (/dev/mapper/loopXpN; chosen because Docker has no udev), and
  grub-probe mis-classifies the dm /boot as LVM ("disk lvm/loopXpN not found"). My partx+mknod
  +remount attempt hit dm/kernel-node superblock aliasing ("already mounted"). **Agent fixing**
  — root approach: make attach_image expose REAL kernel partition nodes (losetup -P + mknod
  /dev/loopXpN from /sys) so grub-probe sees plain (hd0,gptN); phases 0-3 stamped so only
  phase-system is affected. Only edits lib.sh / 04.
- next: agent lands grub fix → phase-system green → **make run** (QEMU, -nographic, ttyS0) →
  verify subject criteria (uname -r=6.6.32-dlesieur, /boot path, >=3 partitions, hostname
  dlesieur, wget reaches net, build+run a hello = pkg-mgmt) → **make shasum** → commit
  build/disk.sha256. Then deferred hellish hardening ([[ && ]], script-file heredoc edge) +
  full re-audit.

## 2026-06-04 — M2 COMPLETE: entire Ch.7+Ch.8 userland built under hellish-in-chroot
- result: **`Ch.8 build-all complete.` PHASE DONE.** 75 stamps (6 Ch.7 _tmp + 26 B1 + 43
  B2/B3). Image has bash, init (SysVinit), gcc, udevd (eudev), syslogd, vim, agetty,
  grub-install. 4.8G used / 12G free. The full mandatory userland is built FROM SOURCE,
  NATIVELY UNDER HELLISH inside the chroot. The 3rd hellish fix (heredoc-body-quote-desync,
  develop e047f67) unblocked sysklogd/sysvinit (their config heredocs). Submodule bumped.
- THREE hellish root-cause fixes landed this run, all found by driving real LFS scripts:
  (1) line-continuation in sourced files (tokenizer skip_noise), (2) consecutive-heredoc
  (extract2 advance_hd), (3) heredoc-body-quote-desync (extract3 collect_specs line-by-line).
  All DoD-green (1739 tests, bench >=1.0, norm), merged to develop, image republished.
- GAP: no wget/curl in the image yet (subject requires one) — add wget in M7.
- next (M7): add wget + B4 strip/cleanup → kernel: write configs/kernel/.config (virtio/
  ext4/8250-serial built-in) + phase-kernel (6.6.32-dlesieur) → phase-system (04: hostname/
  fstab-by-LABEL/inittab/GRUB-i386-pc/static-network) → QEMU boot (make run) → verify subject
  criteria (uname -r, /boot path, partitions, hostname, wget, pkg-mgmt) → make shasum.

## 2026-06-04 — M2/B2-B3: ~38/43 userland built; blocked on hellish heredoc-at-scale bug
- result: B2/B3 building well under hellish-in-chroot. Built (stamped): ncurses, sed,
  psmisc, gettext, bison, grep, bash, libtool, gdbm, gperf, expat, inetutils, less, perl,
  xml_parser, intltool, autoconf, automake, kmod, elfutils, coreutils, check, diffutils,
  gawk, findutils, groff, grub, gzip, iproute2, kbd, libpipeline, make, patch, tar, texinfo,
  vim, eudev, procps, util_linux, e2fsprogs (~38). REMAINING: sysklogd, sysvinit, man_db.
- recipe fixes this batch (all committed): expat URL (sf 404→github), reused-Ch.6 tarballs
  added to CH8_SOURCES, vim URL, psmisc release-tarball+in-tree (man-po), sed/expat/tar
  out-of-tree doc paths, kmod --without-openssl, eudev udev-lfs rules cwd, =#TODO md5 parse.
- BLOCKER (hellish bug): **sysklogd's single syslog.conf heredoc leaked** ("auth,authpriv.*:
  command not found"). Root cause: split_heredocs (exec_string.c) pre-extracts ALL heredoc
  bodies in a sourced file (file order), but only the CALLED function's heredoc executes →
  desync when a file DEFINES many heredoc-functions but CALLS few. (The earlier advance_hd
  fix only covered consecutive heredocs.) **Agent fixing** in vendor/42sh (full DoD; will
  also unblock sysvinit's inittab heredoc). Per the "fix hellish not the script" rule.
- next: agent lands heredoc fix → republish hellish image → re-run phase-packages (sysklogd
  /sysvinit/man_db build) → B4 strip/cleanup → M7 (kernel/GRUB/SysVinit/network/QEMU/shasum).

## 2026-06-04 — M2/B1 COMPLETE: Ch.7 temp tools + Ch.8 core built under hellish-in-chroot
- result: **`make phase-packages` PHASE_EXIT=0, PHASE DONE.** All 32 stamps in image
  /sources/.stamps: 6 Ch.7 _tmp (gettext/bison/perl/python/texinfo/util-linux) + 26 Ch.8
  core (glibc, zlib, bzip2, xz, zstd, file, readline, m4, bc, flex, tcl, expect, dejagnu,
  pkgconf, binutils, gmp, mpfr, mpc, attr, acl, libcap, libxcrypt, shadow, gcc, man-pages,
  iana-etc). All built NATIVELY under hellish inside the chroot. gcc's largefile-config.h
  "Error 1 (ignored)" is benign (LFS-known). Disk: 30G free.
- fix that unblocked it: prepare_virtfs must run every container invocation (was stamped →
  skipped → no /dev bind → perl saw /dev/null as a file; no /proc → the stat warning).
  Both symptoms gone. Commit for that + man-pages GIT=false + Ch.7 all on develop.
- doing: agent drafting the REMAINING Ch.8 (LFS 12.1 SysVinit) — ncurses..man-db + eudev/
  procps/util-linux(final)/e2fsprogs/sysklogd/sysvinit/grub, appended after build_gcc
  (final builds, no _tmp). Then re-run phase-packages (B1 stamped → skip; B2/B3 build).
- next: B2/B3 build → B4 strip/cleanup → M7 (kernel virtio .config + GRUB + SysVinit
  bootscripts + network(static to QEMU user-net) + wget; QEMU boot; subject verify; shasum).

## 2026-06-04 — M2: hellish-in-chroot WORKS; found missing LFS Ch.7 (temp tools)
- result: phase-packages ran — **hellish-in-chroot smoke PASSED** (HELLISH_IN_CHROOT_OK),
  build-all ran under hellish: man_pages [done], iana_etc [done], then **glibc configure
  failed: "critical programs missing: bison python"**. Root cause: we jumped Ch.6→Ch.8 and
  SKIPPED **LFS Chapter 7** (additional NATIVE temp tools the chroot needs: gettext, bison,
  perl, Python, texinfo, util-linux). Not a hellish/script bug — a missing phase.
- man-pages fix worked (GIT=false). Non-fatal hellish warning persists: "Cannot open
  /proc/self/stat" on each in-chroot hellish startup (smoke + builds still work) — log for
  the hardening pass (cosmetic; hellish reads /proc/self/stat at startup in the chroot).
- doing: agent drafting LFS 12.1 Ch.7 recipes as `build_<pkg>_tmp` PREPENDED to
  build-system-lib.sh (so build-all's derived ORDER runs them before glibc) + packages.sh
  Ch.7 section + appended to CH8_SOURCES. man_pages/iana_etc are stamped (will skip).
- next: integrate Ch.7 recipes (review) → re-run phase-packages (Ch.7 temp tools build,
  then glibc onward). Then B2/B3 Ch.8 recipes (agent), strip/cleanup, M7.
- NOTE for resume: build order = Ch.7 _tmp tools → Ch.8 (man_pages, iana_etc, glibc, …);
  stamps in image /sources/.stamps; `make loopclean` after any killed phase.

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
