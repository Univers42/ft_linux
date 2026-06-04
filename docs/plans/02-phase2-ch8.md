# 02 — Phase 2: LFS Chapter 8 (the userland, ~90 packages)

The main subject work. Build every mandatory package from source **inside the chroot**,
in dependency order, idempotently, under hellish. This doc is the authoritative manifest +
recipe template + chroot model so M3–M6 are mechanical.

## Package set = the subject's list, modern versions

The subject's mandatory list (eudev + udev-lfs, Sysklogd, SysVinit, **no** Python/Meson/
OpenSSL) is the LFS SysVinit package *set*. We build that exact set with **modern pinned
versions** and LFS-12.x-adapted instructions (eudev 3.2.x and GRUB 2.12 build via autotools,
so no Meson/Python is pulled in). Versions shared with the toolchain stay in lock-step
([packages.sh](../../scripts/packages.sh)).

## Chroot model (driver: `scripts/02-build-system.sh`)

Already scaffolded ([02-build-system.sh](../../scripts/02-build-system.sh)): attach image,
mount p4→`$LFS`, p2→`$LFS/boot`, bind `/dev`, mount `devpts`/`proc`/`sysfs`/`tmpfs`, EXIT
trap unmounts + detaches. To implement:

1. **Pre-chroot (host-side, in builder):** create `$LFS/{dev,proc,sys,run}`, `/dev/{console,null}`
   (mknod), the LFS dir skeleton (`bin lib lib64 sbin etc var usr/{bin,lib,sbin} tools …`),
   essential files (`/etc/passwd`, `/etc/group`, `/etc/hosts`, `/root`, `/tmp`, login.defs),
   and **stage hellish** → `$LFS/tools/bin/hellish` (+ its `.so` deps, or a static build).
2. **Enter chroot** with a clean env:
   ```
   chroot "$LFS" /tools/bin/hellish /sources/build-all.sh
   #  env -i  HOME=/root  TERM="$TERM"  PS1='(lfs) \u:\w\$ '
   #          PATH=/usr/bin:/usr/sbin:/tools/bin  MAKEFLAGS=-jN  SOURCE_DATE_EPOCH=…
   ```
   `build-all.sh` sources `build-system-lib.sh` + `packages.sh` and runs the `ORDER` loop
   with `step "$pkg-$ver" build_$pkg`. (Fallback: `/bin/bash` per-package, §01.7.)
3. **Idempotent:** stamps under `$LFS/.stamps`; re-running Phase 2 resumes.

## Recipe template (mirrors `build-toolchain-lib.sh`)

```sh
build_<pkg>() {
    local src; src="$(unpack "$<PKG>_URL")"     # fetch (sha256-verified) + extract
    with_clean_build "$src"                      # fresh $src/build, cd in
    ../configure --prefix=/usr <flags…>          # book flags, verbatim
    make
    make check        # where the book runs tests (Tcl/Expect/DejaGNU enable these)
    make install
    <post-install fixups, verbatim from book>
    rm -rf "$src"                                # bound disk
}
```

Each `build_<pkg>` encodes the LFS Ch.8 commands for that package verbatim — flags,
`sed` fixups, doc moves, `.la` removals. Keep ≤ ~30 lines; split helpers if longer.

## Build order — batched (pin versions in `packages.sh`)

Order is the LFS Ch.8 topological order; the validator (§01.2) asserts deps precede each
package. Versions below are the pinned targets (sync ⇄ toolchain where noted).

### B0 — data/skeleton (no compiler)
| pkg | ver | note |
|---|---|---|
| (skeleton) | — | dirs, /dev nodes, /etc/{passwd,group,hosts}, stage hellish |
| Man-pages | 6.7 | docs only |
| Iana-Etc | 20240125 | /etc/{protocols,services} |
| Time Zone Data (tzdata) | 2024a | /usr/share/zoneinfo |

### B1 — core toolchain (chroot becomes self-hosting) → **M3**
| pkg | ver | note |
|---|---|---|
| Glibc (final) | 2.39 | native; locales; nsswitch; ld.so.conf |
| Zlib | 1.3.1 | |
| Bzip2 | 1.0.8 | book patch + shared lib |
| Xz | 5.4.6 | ⇄toolchain |
| File | 5.45 | ⇄toolchain |
| Readline | 8.2 | |
| M4 | 1.4.19 | ⇄toolchain |
| Bc | 6.7.6 | |
| Flex | 2.6.4 | |
| Tcl | 8.6.13 | test infra |
| Expect | 5.45.4 | test infra |
| DejaGNU | 1.6.3 | test infra |
| Pkg-config | 0.29.2 | (pkgconf 2.x also OK) |
| Binutils (final) | 2.42 | ⇄toolchain; run test suite |
| GMP / MPFR / MPC | 6.3.0 / 4.2.1 / 1.3.1 | ⇄toolchain |
| Attr / Acl | 2.5.2 / 2.3.2 | |
| Libcap | 2.69 | |
| Shadow | 4.14.2 | passwd/login; disable groups man |
| **GCC (final)** | 13.2.0 | ⇄toolchain; big; run test suite; `cc` symlink |

### B2 — core libraries & utilities → **M4**
| pkg | ver | note |
|---|---|---|
| Ncurses | 6.4 | ⇄toolchain; widec |
| Sed | 4.9 | ⇄toolchain |
| Psmisc | 23.7 | |
| Gettext | 0.22.5 | |
| Bison | 3.8.2 | |
| Grep | 3.11 | ⇄toolchain |
| Bash (final) | 5.2.21 | ⇄toolchain; /bin/sh symlink |
| Libtool | 2.4.7 | |
| GDBM | 1.23 | |
| Gperf | 3.1 | |
| Expat | 2.6.2 | |
| Inetutils | 2.5 | ping/telnet/ftp; **network tools** |
| Less | 643 | |
| Perl | 5.38.2 | |
| XML::Parser | 2.46 | perl module |
| Intltool | 0.51.0 | |
| Autoconf / Automake | 2.72 / 1.16.5 | |
| Coreutils | 9.4 | ⇄toolchain; ls/cp/… |
| Check | 0.15.2 | test framework |
| Diffutils | 3.10 | ⇄toolchain |
| Gawk | 5.3.0 | ⇄toolchain |
| Findutils | 4.9.0 | ⇄toolchain |
| Groff | 1.23.0 | man formatting |
| Gzip | 1.13 | ⇄toolchain |
| IPRoute2 | 6.7.0 | ip/ss; **network** |
| Kbd | 2.6.4 | keymaps |
| Libpipeline | 1.5.7 | man-db dep |
| Make | 4.4.1 | ⇄toolchain |
| Patch | 2.7.6 | ⇄toolchain |
| Tar | 1.35 | ⇄toolchain |
| Texinfo | 7.1 | |
| Vim | 9.1 | editor |

### B3 — system, device, init → **M5**
| pkg | ver | note |
|---|---|---|
| Eudev | 3.2.14 | **module loader (subject)**; autotools, no meson |
| (udev-lfs rules) | 20230818 | extra rules tarball (optional; eudev ships base rules) |
| Util-linux | 2.39.3 | mount/blkid/… |
| E2fsprogs | 1.47.0 | mkfs.ext4/fsck |
| Procps-ng | 4.0.4 | ps/top/sysctl |
| Kmod | 31 | modprobe/lsmod |
| Man-DB | 2.12.0 | man |
| Sysklogd | 2.6.0 | syslogd/klogd |
| SysVinit | 3.08 | **init (subject)**; /etc/inittab |
| GRUB | 2.12 | **bootloader (subject)**; i386-pc |

### B4 — finalize → **M6**
- Strip debug symbols (`strip` libs/bins, keep needed), remove `/usr/share/doc` bloat &
  `.la` files, clean `/tmp`, remove `/tools` (no longer needed post-bootstrap) **except**
  the staged hellish if we want it on the target (decide: keep `/usr/bin/hellish`? optional
  bonus — the target could even run hellish. Document; not required by subject).
- `ldconfig`; verify `ldd` on key binaries; `find /usr -name '*.la' -delete`.

## Per-batch exit criteria

A batch is done when: every `build_<pkg>` stamped; a smoke test passes inside the chroot
(`gcc` compiles + links a hello world after B1; `ls`/`bash`/`grep` work after B2; `udevadm`,
`init --version`, `grub-install --version` present after B3); conformance still green;
committed on `develop`.

## Notes / gotchas

- **Glibc locales**: install a minimal set (C.UTF-8, en_US.UTF-8) — full set is huge/slow.
- **GCC final** is the longest single build — runs with the resource-bounded `-j` (§01.5).
- **Tcl/Expect/DejaGNU** must precede Binutils/GCC final so their test suites can run.
- **Inetutils + IPRoute2** give us `ping`/`ip`; `wget`/`curl` for the subject's network req
  is handled in `04-kernel-boot-net.md` (curl needs no extra deps for http; built or add to set).
- Subject lists **Procps** (= procps-ng) and **Man-DB** — both in B3/B2.
- If a package needs an unlisted dep at a modern version, add it + note it in `PROGRESS.md`.
