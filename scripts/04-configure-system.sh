#!/bin/bash
# Phase 4 — Final system configuration (LFS book chapters 9-11).
#
# - Installs lfs-bootscripts (Ch.9.2) — provides /etc/rc.d and network service
#   scripts (ipv4-static) that 01–03 rely on at boot time.
# - Writes hostname, /etc/hosts, fstab, inittab with serial console on ttyS0,
#   static QEMU user-mode network (10.0.2.15/24), locale, timezone.
# - Installs GRUB (i386-pc) onto the loop device and writes grub.cfg with the
#   console= kernel parameters so -nographic QEMU works out of the box.
# - Removes the root password for passwordless evaluation login.
#
# Partition layout (from 00-init-disk.sh, GPT):
#   p1  bios_grub (2 MiB, no FS — GRUB core landing zone)
#   p2  /boot     ext4  LABEL=boot   ← grub sees this as (hd0,gpt2)
#   p3  swap             LABEL=swap
#   p4  /         ext4  LABEL=root

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/packages.sh
. "$(dirname "$0")/packages.sh"

require_in_container
require_root
phase_start "04-configure-system"

LOOP="$(attach_image "$IMG_PATH")"
# arm_cleanup handles EXIT + SIGTERM + SIGINT (hellish does not fire EXIT on SIGTERM).
arm_cleanup "$LOOP"

sleep 1

mkdir -p "$LFS"
mount "$(part "$LOOP" 4)" "$LFS"
mount "$(part "$LOOP" 2)" "$LFS/boot"
mount --bind /dev     "$LFS/dev"
mount -t devpts devpts -o gid=5,mode=620 "$LFS/dev/pts"
mount -t proc   proc   "$LFS/proc"
mount -t sysfs  sysfs  "$LFS/sys"

# ============================================================
# 1. lfs-bootscripts (LFS Ch.9.2)
# ============================================================
# The bootscripts tarball provides the rc, network/ipv4-static, udev, and
# other service scripts.  We fetch it into the source cache, extract into
# $LFS/sources, then install via chroot (bash + make are already there from
# phase 2; the Makefile copies files only, no compilation step).
info "Installing lfs-bootscripts-${LFS_BOOTSCRIPTS_VERSION}"

BOOTSCRIPTS_TAR="$(fetch "$LFS_BOOTSCRIPTS_URL")"
BOOTSCRIPTS_SRC="$(extract "$BOOTSCRIPTS_TAR" "$LFS/sources")"

# The Makefile's "install" target needs DESTDIR="" (it hard-codes paths to /
# inside the chroot).  Some versions also need "make install" run from the
# extracted directory; we use env -i so the chroot environment is clean.
chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/bin:/usr/sbin:/bin:/sbin \
    /bin/bash -c "cd /sources/$(basename "$BOOTSCRIPTS_SRC") && make install"

# ============================================================
# 2. Hostname (subject requirement: student login)
# ============================================================
info "Setting hostname to $HOSTNAME_TARGET"
echo "$HOSTNAME_TARGET" > "$LFS/etc/hostname"

# /etc/sysconfig/rc.site: read by the bootscripts on startup.
mkdir -p "$LFS/etc/sysconfig"
cat > "$LFS/etc/sysconfig/rc.site" <<EOF
# lfs-bootscripts rc.site — site-level overrides.
HOSTNAME="$HOSTNAME_TARGET"
# Keep the clock in UTC (correct for QEMU).
CLOCKPARAMS="--utc"
EOF

cat > "$LFS/etc/hosts" <<EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME_TARGET
::1         localhost ip6-localhost ip6-loopback
EOF

# ============================================================
# 3. /etc/fstab — uses LABELs set in phase 0 (00-init-disk.sh)
# ============================================================
info "Writing /etc/fstab"
cat > "$LFS/etc/fstab" <<'EOF'
# <device>      <mount>  <type>  <options>           <dump>  <pass>
LABEL=root      /        ext4    defaults,noatime    0       1
LABEL=boot      /boot    ext4    defaults,noatime    0       2
LABEL=swap      none     swap    pri=1               0       0
proc            /proc    proc    nosuid,noexec,nodev 0       0
sysfs           /sys     sysfs   nosuid,noexec,nodev 0       0
devpts          /dev/pts devpts  gid=5,mode=620      0       0
tmpfs           /run     tmpfs   defaults            0       0
EOF

# ============================================================
# 4. Network — static, QEMU user-mode NAT addresses
# ============================================================
# QEMU -netdev user assigns the VM 10.0.2.15/24.  The host is 10.0.2.2
# (default gateway) and acts as a DNS forwarder at 10.0.2.3.  There is no
# DHCP client in the initial system, so we configure a static address using
# the ipv4-static service provided by lfs-bootscripts.
info "Configuring static network for QEMU user-mode (eth0 10.0.2.15/24)"
mkdir -p "$LFS/etc/sysconfig"
cat > "$LFS/etc/sysconfig/ifconfig.eth0" <<'EOF'
ONBOOT=yes
IFACE=eth0
SERVICE=ipv4-static
IP=10.0.2.15
GATEWAY=10.0.2.2
PREFIX=24
BROADCAST=10.0.2.255
EOF

cat > "$LFS/etc/resolv.conf" <<'EOF'
# QEMU user-mode NAT DNS forwarder.
nameserver 10.0.2.3
EOF

# ============================================================
# 5. SysVinit /etc/inittab — with serial console on ttyS0
# ============================================================
# -nographic QEMU maps the serial port (ttyS0) to stdio.  Without an agetty
# on ttyS0 the boot is silent; add it at the end of the standard run-levels
# alongside the virtual terminal entries.  Keep tty1 so a graphical/VNC run
# also works.
info "Writing /etc/inittab (runlevel 3, serial on ttyS0)"
cat > "$LFS/etc/inittab" <<'EOF'
# /etc/inittab — SysVinit configuration (LFS 12.1 Ch.9.8).

# Default runlevel.
id:3:initdefault:

# System initialisation.
si::sysinit:/etc/rc.d/init.d/rc S

# Runlevel scripts.
l0:0:wait:/etc/rc.d/init.d/rc 0
l1:S1:wait:/etc/rc.d/init.d/rc 1
l2:2:wait:/etc/rc.d/init.d/rc 2
l3:3:wait:/etc/rc.d/init.d/rc 3
l4:4:wait:/etc/rc.d/init.d/rc 4
l5:5:wait:/etc/rc.d/init.d/rc 5
l6:6:wait:/etc/rc.d/init.d/rc 6

# Ctrl-Alt-Delete.
ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now

# Single-user shell.
su:S016:once:/sbin/sulogin

# Virtual consoles (kept so VNC/graphical also works).
1:2345:respawn:/sbin/agetty --noclear tty1 9600
2:2345:respawn:/sbin/agetty tty2 9600

# Serial console — primary login path for QEMU -nographic.
# --keep-baud honours the baud rate negotiated by the remote; 115200 is the
# first fallback.
s0:2345:respawn:/sbin/agetty --keep-baud 115200 ttyS0 vt220
EOF

# ============================================================
# 6. Locale / timezone
# ============================================================
echo 'LANG=C.UTF-8' > "$LFS/etc/locale.conf"
ln -sf /usr/share/zoneinfo/UTC "$LFS/etc/localtime" 2>/dev/null || true

# ============================================================
# 7. GRUB — BIOS (i386-pc) install + grub.cfg
# ============================================================
# /boot is partition 2 on a GPT disk → GRUB refers to it as (hd0,gpt2).
# The kernel line appends both console= options so that serial and the VGA
# framebuffer receive the same output (Linux writes to both when two consoles
# are listed; the last one listed becomes the "preferred" console for /dev/console).
info "Installing GRUB to $LOOP (i386-pc, /boot = gpt2)"
mkdir -p "$LFS/boot/grub"
cat > "$LFS/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5

menuentry "ft_linux ${KERNEL_FULL}" {
    set root=(hd0,gpt2)
    linux /vmlinuz-${KERNEL_FULL} root=LABEL=root ro console=ttyS0,115200 console=tty0
    # initrd not used — we rely on built-in kernel drivers (defconfig + virtio).
}
EOF

# --modules="part_gpt ext2": GRUB needs part_gpt to read the GPT partition
# table and ext2 to read /boot (ext4 is backward-compatible with the ext2
# module for the purpose of reading the kernel image and grub files).
grub-install \
    --target=i386-pc \
    --boot-directory="$LFS/boot" \
    --modules="part_gpt ext2" \
    "$LOOP"

# ============================================================
# 8. Root password — passwordless for evaluation
# ============================================================
# passwd -d removes the password so root can log in without one.
# The serial console agetty line above allows direct login.
info "Removing root password (passwordless login for evaluation)"
chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/bin:/usr/sbin:/bin:/sbin \
    /bin/bash -c "passwd -d root" || true

phase_end
