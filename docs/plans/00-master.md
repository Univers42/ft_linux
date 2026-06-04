# 00 — Master Plan: Finish ft_linux & harden hellish

> Autonomous, Docker-only, sudo-free. This is the index; each section links to the
> detailed doc. Source of approved strategy: `.claude/plans/snuggly-soaring-hanrahan.md`.
> Working practices for hellish: `.claude/hellish-workflow.md`. Project rules:
> `.claude/CLAUDE.md`.

## Mission

Deliver a from-source LFS distribution that boots in QEMU, built **entirely under
hellish** (our 42sh) inside Docker, with **zero host pollution and no sudo**. Each build
script hellish has to run is also an opportunity to harden hellish (fix the shell, not the
script). Deliverable to the school = `shasum` of the disk image (`make shasum` →
`build/disk.sha256`).

## Subject acceptance criteria (verify all)

| Constraint | Target |
|---|---|
| Kernel | ≥ 4.0 → **6.6.32**, `uname -r` = `6.6.32-dlesieur` |
| Kernel binary / sources | `/boot/vmlinuz-6.6.32-dlesieur` / `/usr/src/kernel-6.6.32` |
| Hostname | `dlesieur` |
| Partitions | ≥ 3 (`/boot`, swap, `/`; we have 4 incl. bios_grub) |
| Module loader / init / bootloader | **eudev** / **SysVinit** / **GRUB 2** (BIOS) |
| Network | `curl` **or** `wget` works in the final system |
| Package mgmt | possible to build+install a new package on the final system |
| All mandatory packages | built from source (list in `02-phase2-ch8.md`) |

## The two hard rules

1. **Docker only, never sudo, never touch the host.** Only host tools: `docker`, `qemu`.
2. **Pure hellish runs the build scripts.** Failure under hellish (but not bash) ⇒ fix
   hellish per `.claude/hellish-workflow.md`. Failure under bash too ⇒ real script bug.

## Current state (accurate)

- **Phase 0** disk — done, validated under hellish.
- **Phase 1** toolchain — builds under bash (oracle); under hellish reaches binutils
  `configure` (the live frontier; see `03-hellish.md`).
- **Phase 2** Ch.8 (~90 pkgs) — **stub** (the main work; see `02-phase2-ch8.md`).
- **Phase 3** kernel — works but uses `defconfig`; needs committed virtio `.config`.
- **Phase 4** config — done (hostname/fstab/inittab/GRUB/network stub).
- Docker bakes hellish; `RUNNER := hellish`; conformance + regression suites exist & green.

## Milestone map

| M | Goal | Doc |
|---|---|---|
| **M0** | Unblock: conformance cases (`exec>>(tee)`, `set -e` pipeline, `[[&&]]`), fix `MAKEFLAGS`, root-cause+fix binutils-`configure`, republish image | `03-hellish.md` |
| **M1** | Toolchain end-to-end under hellish (stamps recorded) | `02` §toolchain, `03` |
| **M2** | Ch.8 scaffolding: `build-system-lib.sh` + `packages.sh` entries + chroot driver + in-chroot hellish | `01`, `02` |
| **M3** | B1 — chroot entry, virtual FS, final glibc + libstdc++ + gcc | `02` |
| **M4** | B2 — core libs/utils (zlib…bash, coreutils, sed/grep/gawk, …) | `02` |
| **M5** | B3 — system pkgs (eudev, util-linux, e2fsprogs, shadow, sysvinit, …) | `02` |
| **M6** | B4 — strip + cleanup | `02` |
| **M7** | Kernel `.config`, boot in QEMU, network + pkg-mgmt verify, `make shasum` | `04` |

Each milestone ends **green + committed** on `develop`. Any hellish gap hit mid-milestone
triggers the fix-loop (`03-hellish.md`) before proceeding.

## Document set

- `01-architecture.md` — the DSA/orchestration design (the "ultrathink" core).
- `02-phase2-ch8.md` — full ordered package manifest, recipe template, chroot model.
- `03-hellish.md` — conformance matrix, binutils diagnosis, known gaps, image loop.
- `04-kernel-boot-net.md` — kernel config, GRUB, SysVinit, network, pkg-mgmt verify.
- `05-autonomy.md` — execution loop, agent team, token budget, guardrails, STOP rules.
- `PROGRESS.md` — living decision/progress log (append every milestone).

## Definition of "done" for the whole project

`make build` (RUNNER=hellish) green → `make run` boots `6.6.32-dlesieur` to a login shell
→ in the VM all acceptance criteria above hold → `make shasum` written and committed →
hellish suites (1703 + bench geomean ≥1.0 + norm) green with every build construct covered
by a regression test.
