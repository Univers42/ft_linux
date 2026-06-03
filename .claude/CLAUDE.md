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

## Architecture

```
ft_linux/
├── docker/                ← build environment (Debian 12 + LFS toolchain prereqs)
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── entrypoint.sh
├── scripts/               ← LFS build phases, run inside the container
│   ├── lib.sh             ← shared bash helpers, constants, logging
│   ├── 00-init-disk.sh    ← create + partition + format the 20 GB image
│   ├── 01-build-toolchain.sh ← LFS ch. 5-6: cross-toolchain
│   ├── 02-build-system.sh    ← LFS ch. 8: 80+ packages in chroot
│   ├── 03-build-kernel.sh    ← LFS ch. 10: kernel 6.6.32 with -dlesieur suffix
│   ├── 04-configure-system.sh ← LFS ch. 9-11: hostname, fstab, network, GRUB
│   └── vm-run.sh          ← QEMU launcher
├── configs/
│   └── kernel/.config     ← saved kernel config (committed)
├── build/                 ← gitignored: disk image and logs
│   ├── ft_linux.img       ← 20 GB raw, the deliverable
│   ├── disk.sha256        ← submission artifact
│   └── logs/              ← per-phase build logs
├── docs/en.subject.pdf    ← project subject
└── Makefile               ← single entry point for everything
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

# Phases individually (each is re-entrant):
make phase-disk
make phase-toolchain
make phase-packages
make phase-kernel
make phase-system
```

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

- Base: `debian:12-slim`
- Installs LFS host requirements (gcc, make, bison, gawk, texinfo, etc.) — see Dockerfile
- Runs `--privileged` only for loop device + chroot (no kernel modules touched)
- Mounts:
  - `..:/project:ro` — source tree (read-only)
  - `../build:/output` — disk image and logs (read-write)
  - `lfs-tree` (named volume) — long-lived `/mnt/lfs` working tree across phases

The container writes **only** to `./build/` and its own named volume.
`docker volume rm lfs-tree` wipes everything cleanly.

---

## What Claude Should Help With

- Debug individual build phase scripts (gcc build failures, missing deps, configure flags)
- Tune the kernel `.config` for QEMU virtio
- GRUB configuration for the disk image
- SysVinit boot scripts (network, syslog, agetty)
- Network configuration (DHCP via inetutils or static)
- Generate the shasum for submission

## What Claude Must NOT Do

- Run `sudo apt install`, `pip install`, or any host package installer
- Modify anything outside `/home/dlesieur/Documents/ft_linux/`
- Commit `build/ft_linux.img` (20 GB) or anything from `build/`
- Run kernel builds outside the container
- Suggest "just install X on the host" as a workaround — always fix in Dockerfile

If a build fails, the answer is **never** to install something on the host.