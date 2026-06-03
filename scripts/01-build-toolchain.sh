#!/bin/bash
# Phase 1 — LFS Ch. 4-6: filesystem skeleton + cross-toolchain.
#
# This script:
#   1. Mounts the disk image at $LFS
#   2. Creates the LFS filesystem skeleton (/tools, /sources, /usr, …)
#   3. Builds the cross-toolchain (Ch. 5: binutils, gcc, headers, glibc, libstdc++)
#   4. Cross-compiles temporary tools (Ch. 6: 17 packages)
#
# Each step is wrapped in step() which skips it if a stamp marker exists
# under $LFS/.stamps/. To force a rebuild of one step, delete its stamp file
# and re-run.
#
# Heavy: ~30-60 min on a fast box, hours on slow ones.

. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/packages.sh"
. "$(dirname "$0")/build-toolchain-lib.sh"

require_in_container
require_root
phase_start "01-build-toolchain"

# --------------------------------------------------------------------------
# Mount the image
# --------------------------------------------------------------------------
info "Attaching disk image"
LOOP="$(attach_image "$IMG_PATH")"
trap 'umount -R "$LFS" 2>/dev/null || true; detach_image "$LOOP"' EXIT
sleep 1

mkdir -p "$LFS"
# Be defensive: tear down any leftover mounts (from a prior crashed run) first.
umount -R "$LFS" 2>/dev/null || true
mount "$(part "$LOOP" 4)" "$LFS"
mkdir -p "$LFS/boot"
mount "$(part "$LOOP" 2)" "$LFS/boot"

# --------------------------------------------------------------------------
# LFS Ch. 4 — filesystem skeleton
# --------------------------------------------------------------------------
init_skeleton() {
    mkdir -pv "$LFS"/{etc,var,tools,sources} "$LFS"/usr/{bin,lib,sbin}
    for i in bin lib sbin; do
        ln -sfv "usr/$i" "$LFS/$i"
    done
    case "$(uname -m)" in
        x86_64) mkdir -pv "$LFS/lib64" ;;
    esac
    chmod -v a+wt "$LFS/sources"
}
step "00-skeleton" init_skeleton

# Toolchain env — every cross-compiler invocation needs these.
export PATH="$LFS/tools/bin:/usr/bin:/usr/sbin"
export LC_ALL=POSIX
export CONFIG_SITE="$LFS/usr/share/config.site"

# --------------------------------------------------------------------------
# LFS Ch. 5 — cross-toolchain
# --------------------------------------------------------------------------
step "ch5-binutils-pass1"  build_binutils_pass1
step "ch5-gcc-pass1"       build_gcc_pass1
step "ch5-linux-headers"   build_linux_headers
step "ch5-glibc"           build_glibc
step "ch5-libstdcxx"       build_libstdcxx

# --------------------------------------------------------------------------
# LFS Ch. 6 — cross-compile temporary tools
# --------------------------------------------------------------------------
step "ch6-m4"          build_m4
step "ch6-ncurses"     build_ncurses
step "ch6-bash"        build_bash
step "ch6-coreutils"   build_coreutils
step "ch6-diffutils"   build_diffutils
step "ch6-file"        build_file
step "ch6-findutils"   build_findutils
step "ch6-gawk"        build_gawk
step "ch6-grep"        build_grep
step "ch6-gzip"        build_gzip
step "ch6-make"        build_make
step "ch6-patch"       build_patch
step "ch6-sed"         build_sed
step "ch6-tar"         build_tar
step "ch6-xz"          build_xz
step "ch6-binutils-pass2" build_binutils_pass2
step "ch6-gcc-pass2"      build_gcc_pass2

info ""
info "Cross-toolchain build complete."
info "  toolchain prefix: $LFS/tools"
info "  next:             make phase-packages   (LFS Ch. 7-8, chroot phase)"

phase_end
