# 04 — Kernel, boot, network, and submission

Covers Phase 3 (kernel), Phase 4 (system config), and the end-to-end boot + acceptance.
Goal: `make run` boots `6.6.32-dlesieur` to a login shell with working network and the
ability to install a new package.

## Kernel (Phase 3 — `03-build-kernel.sh`)

Linux 6.6.32, `CONFIG_LOCALVERSION="-dlesieur"` → `uname -r` = `6.6.32-dlesieur`, binary
`/boot/vmlinuz-6.6.32-dlesieur`, sources at `/usr/src/kernel-6.6.32`. Today the script
falls back to `make defconfig` (not virtio-tuned). **Deliverable: a committed
`configs/kernel/.config`.**

Build it from `defconfig` + the QEMU-virtio essentials, then commit the result so the build
is reproducible and bootable. Must be **built-in (`=y`), not modules**, so no initramfs is
needed:

| Area | Symbols (=y) |
|---|---|
| LocalVersion | `CONFIG_LOCALVERSION="-dlesieur"`, `CONFIG_LOCALVERSION_AUTO=n` |
| Block / virtio | `VIRTIO`, `VIRTIO_PCI`, `VIRTIO_BLK`, `VIRTIO_NET`, `VIRTIO_CONSOLE` |
| FS | `EXT4_FS`, `FS_MBCACHE`, `JBD2`, `TMPFS`, `PROC_FS`, `SYSFS`, `DEVTMPFS`, `DEVTMPFS_MOUNT` |
| Console/TTY | `TTY`, `SERIAL_8250`, `SERIAL_8250_CONSOLE`, `VT`, `VT_CONSOLE` |
| Net | `NET`, `INET`, `PACKET`, `UNIX`, basic IPv4, `CONFIG_IP_PNP`+DHCP optional |
| Exec/Binfmt | `BINFMT_ELF`, `BINFMT_SCRIPT` |
| Misc | `BLK_DEV_INITRD=n` (no initramfs), `PRINTK`, `MULTIUSER` |

After build, the script already writes `build/kernel.config.saved`; **copy a curated one to
`configs/kernel/.config` and commit it.** Verify the bzImage lands at the subject path and
`make modules_install` (if any modules) targets the image's `/lib/modules`.

> Kernel builds run in the **builder container** (has gcc/bc/flex/bison/libelf/libssl), not
> in the chroot — keeps the host clean and the chroot minimal.

## Bootloader (GRUB, Phase 4)

Legacy BIOS on the GPT `bios_grub` stub partition (p1): `grub-install --target=i386-pc
--boot-directory=$LFS/boot <loop>`. `grub.cfg` (or `grub-mkconfig`) entry:
`linux /vmlinuz-6.6.32-dlesieur root=LABEL=lfsroot ro console=ttyS0,115200 console=tty0`.
Match the root **LABEL** the disk was formatted with in Phase 0 (`fstab` uses LABEL too).

## Init & system config (Phase 4 — `04-configure-system.sh`)

Already implemented; verify/extend for the *real* userland now present:
- `/etc/hostname` = `dlesieur`; `/etc/hosts` with `127.0.1.1 dlesieur`.
- `/etc/fstab` by **LABEL** (root, /boot, swap) — matches Phase 0 labels.
- `/etc/inittab` (SysVinit): sysinit → rc → agetty on `ttyS0` (serial, for `make run
  nographic`) **and** `tty1`. Runlevels via `/etc/rc.d/` (LFS bootscripts).
- **LFS bootscripts** (the `lfs-bootscripts` set): `mountvirtfs`, `mountfs`, `swap`,
  `udev` (eudev: `udevd` + `udevadm trigger`), `sysklogd`, `network`, `localnet`,
  `setclock`. Install under `/etc/rc.d/init.d` + runlevel symlinks.
- Passwordless (or known) root for evaluation; create the login.

## Network (subject: curl OR wget must work)

- **Interface bring-up via eudev + a bootscript.** Static or DHCP:
  - *Simplest robust:* a `network` bootscript that runs `ip link set eth0 up` +
    DHCP. We need a DHCP client — `dhcpcd` is **not** in the subject set; `inetutils`/
    `iproute2` don't ship one. Options: (a) static IP config matching QEMU user-net
    (`10.0.2.15/24`, gw `10.0.2.2`, DNS `10.0.2.3`) — **deterministic, no extra package**;
    (b) add a small DHCP client to the package set. **Decision: static config to QEMU
    user-net defaults** (zero extra deps, always works under `make run`); document how to
    switch to DHCP. Write `/etc/resolv.conf` with `nameserver 10.0.2.3`.
- **HTTP client:** the subject says `curl` **or** `wget`. Neither is in the mandatory list,
  but the system must have one. **Decision: build `wget`** (small, depends only on what we
  have; OpenSSL not required for plain HTTP, but for HTTPS we'd add OpenSSL). To satisfy
  "reach the internet" cheaply, ship `wget` (HTTP) + document adding OpenSSL for HTTPS.
  Alternatively build `curl`. Pick `wget` first; add to `packages.sh`/`build-system-lib.sh`.
- **Verify in the booted VM:** `ip addr`, `ping -c1 10.0.2.2`, `wget -qO- http://example.com`
  (QEMU user-net provides outbound). If `make run` uses `-netdev user`, outbound works.

## Package management possible (subject)

"Possible to install a new package on the final system" = the system has a working
toolchain + make + tar + a package can be `./configure && make && make install`. Since we
built gcc/binutils/make/tar/etc. into the target, this already holds. **Verify** by, in the
booted VM, building a tiny autotools package (or `gcc hello.c -o hello`) and running it.
Optionally drop a minimal `pkg-install` helper script documenting the flow.

## End-to-end + submission (M7)

1. `make build` (RUNNER=hellish) green across all phases.
2. `make run` → boots to `dlesieur login:` on serial; log in.
3. In VM, assert acceptance (`00-master.md` table): `uname -r`, kernel path, partitions
   (`lsblk`/`df`), hostname, `wget` fetches a URL, build+run a hello-world.
4. `make shasum` → `build/disk.sha256`; **commit that file** (never the image).
5. Record results in `PROGRESS.md`.

## QEMU notes (`scripts/vm-run.sh`, host)

Boots the raw image `-boot c`, virtio disk + `-netdev user` net, `-nographic` →
`console=ttyS0`. Ensure the kernel `.config` has 8250 serial + virtio so the console and
disk appear. KVM if available; plain TCG otherwise (slower, still boots).
