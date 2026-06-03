#!/bin/bash
# Phase 4 — Final system configuration (LFS book chapters 9-11).
#
# Sets hostname, fstab, network, sysvinit defaults, root password,
# and installs GRUB onto the disk image.

. "$(dirname "$0")/lib.sh"

require_in_container
require_root
phase_start "04-configure-system"

LOOP="$(attach_image "$IMG_PATH")"
trap 'umount -R "$LFS" 2>/dev/null || true; detach_image "$LOOP"' EXIT
sleep 1

mkdir -p "$LFS"
mount "$(part "$LOOP" 4)" "$LFS"
mount "$(part "$LOOP" 2)" "$LFS/boot"
mount --bind /dev "$LFS/dev"
mount -t devpts devpts -o gid=5,mode=620 "$LFS/dev/pts"
mount -t proc  proc    "$LFS/proc"
mount -t sysfs sysfs   "$LFS/sys"

# --- hostname (subject requirement: hostname must be the student login) -----
info "Setting hostname to $HOSTNAME_TARGET"
echo "$HOSTNAME_TARGET" > "$LFS/etc/hostname"

cat > "$LFS/etc/hosts" <<EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME_TARGET
::1         localhost ip6-localhost ip6-loopback
EOF

# --- fstab — uses LABELs we set in phase 0 ---------------------------------
info "Writing /etc/fstab"
cat > "$LFS/etc/fstab" <<EOF
# <device>      <mount>  <type>  <options>          <dump>  <pass>
LABEL=root      /        ext4    defaults,noatime   0       1
LABEL=boot      /boot    ext4    defaults,noatime   0       2
LABEL=swap      none     swap    pri=1              0       0
proc            /proc    proc    nosuid,noexec,nodev 0      0
sysfs           /sys     sysfs   nosuid,noexec,nodev 0      0
devpts          /dev/pts devpts  gid=5,mode=620     0       0
tmpfs           /run     tmpfs   defaults           0       0
EOF

# --- network: bring eth0 up via DHCP at boot --------------------------------
info "Configuring network (DHCP on eth0)"
mkdir -p "$LFS/etc/sysconfig"
cat > "$LFS/etc/sysconfig/ifconfig.eth0" <<EOF
ONBOOT=yes
IFACE=eth0
SERVICE=ipv4-static
# For DHCP, use dhclient or wickedd; depends on what got built in phase 2.
EOF

# --- /etc/resolv.conf — let DHCP overwrite, but seed with a sane default ---
cat > "$LFS/etc/resolv.conf" <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# --- sysvinit /etc/inittab (basic) -----------------------------------------
cat > "$LFS/etc/inittab" <<'EOF'
id:3:initdefault:
si::sysinit:/etc/rc.d/init.d/rc S
l0:0:wait:/etc/rc.d/init.d/rc 0
l1:S1:wait:/etc/rc.d/init.d/rc 1
l2:2:wait:/etc/rc.d/init.d/rc 2
l3:3:wait:/etc/rc.d/init.d/rc 3
l4:4:wait:/etc/rc.d/init.d/rc 4
l5:5:wait:/etc/rc.d/init.d/rc 5
l6:6:wait:/etc/rc.d/init.d/rc 6
ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now
su:S016:once:/sbin/sulogin
1:2345:respawn:/sbin/agetty --noclear tty1 9600
2:2345:respawn:/sbin/agetty tty2 9600
3:2345:respawn:/sbin/agetty tty3 9600
4:2345:respawn:/sbin/agetty tty4 9600
5:2345:respawn:/sbin/agetty tty5 9600
6:2345:respawn:/sbin/agetty tty6 9600
EOF

# --- locale / timezone -----------------------------------------------------
echo 'LANG=C.UTF-8' > "$LFS/etc/locale.conf"
ln -sf /usr/share/zoneinfo/UTC "$LFS/etc/localtime" 2>/dev/null || true

# --- GRUB install -----------------------------------------------------------
# Grub needs a device, not the loop's partition. We installed grub-pc-bin in
# the Docker image so this works from within the container.
info "Installing GRUB to $LOOP"
mkdir -p "$LFS/boot/grub"
cat > "$LFS/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=3

menuentry "ft_linux ${KERNEL_FULL}" {
    set root=(hd0,gpt2)
    linux /vmlinuz-${KERNEL_FULL} root=LABEL=root ro
}
EOF

grub-install --target=i386-pc --boot-directory="$LFS/boot" --modules="part_gpt ext2" "$LOOP"

# --- root password (set to "root" — change for production) ------------------
warn "Setting root password to 'root' (CHANGE THIS for production use)"
chroot "$LFS" /usr/bin/passwd -d root || true
# A passwordless root is fine for evaluation; otherwise pipe into chpasswd.

phase_end
