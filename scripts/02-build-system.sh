#!/bin/bash
# Phase 2 — Build the final system inside a chroot (LFS book chapter 8).
#
# Uses the toolchain from phase 1 to build all mandatory packages directly
# into the disk image's root partition.

. "$(dirname "$0")/lib.sh"

require_in_container
require_root
phase_start "02-build-system"

info "Attaching disk image"
LOOP="$(attach_image "$IMG_PATH")"
trap 'umount -R "$LFS" 2>/dev/null || true; detach_image "$LOOP"' EXIT
sleep 1

mkdir -p "$LFS"
mount "$(part "$LOOP" 4)" "$LFS"
mount "$(part "$LOOP" 2)" "$LFS/boot"

# Virtual filesystems required for chroot
mount --bind /dev "$LFS/dev"
mount -t devpts devpts -o gid=5,mode=620 "$LFS/dev/pts"
mount -t proc proc "$LFS/proc"
mount -t sysfs sysfs "$LFS/sys"
mount -t tmpfs tmpfs "$LFS/run"

# --------------------------------------------------------------------------
# Enter the chroot and build packages.
# In a real run, the chroot block would source a manifest and build every
# mandatory package in dependency order. Kept minimal here.
# --------------------------------------------------------------------------
warn "Phase 2 chroot package build is not yet implemented in this skeleton."
warn "Follow LFS book Ch. 8. Build order matters — start with glibc, then"
warn "zlib, bzip2, xz, file, readline, m4, bc, flex, binutils, gmp, mpfr,"
warn "mpc, attr, acl, libcap, shadow, gcc, … (see book for the full chain)."
warn "Reference: https://www.linuxfromscratch.org/lfs/view/stable/chapter08/"

# Example chroot invocation (uncomment when a manifest is ready):
# chroot "$LFS" /usr/bin/env -i \
#     HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
#     PATH=/usr/bin:/usr/sbin \
#     /bin/bash --login -c '/sources/build-all.sh'

phase_end
