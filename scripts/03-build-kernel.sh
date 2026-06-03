#!/bin/bash
# Phase 3 — Build the Linux kernel (LFS book chapter 10).
#
# Subject requirements:
#   - kernel version >= 4.0  → we use 6.6.32 LTS
#   - uname -r must show "${KERNEL_VERSION}-${STUDENT_LOGIN}"  (6.6.32-dlesieur)
#   - kernel binary at /boot/vmlinuz-6.6.32-dlesieur
#   - kernel sources at /usr/src/kernel-6.6.32

. "$(dirname "$0")/lib.sh"

require_in_container
require_root
phase_start "03-build-kernel"

KERN_TARBALL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"
KERN_TARBALL="/output/sources/linux-${KERNEL_VERSION}.tar.xz"
mkdir -p /output/sources

if [[ ! -f "$KERN_TARBALL" ]]; then
    info "Downloading kernel ${KERNEL_VERSION}"
    curl -fL -o "$KERN_TARBALL" "$KERN_TARBALL_URL"
fi

# Attach the disk image
LOOP="$(attach_image "$IMG_PATH")"
trap 'umount -R "$LFS" 2>/dev/null || true; detach_image "$LOOP"' EXIT
sleep 1

mkdir -p "$LFS"
mount "$(part "$LOOP" 4)" "$LFS"
mount "$(part "$LOOP" 2)" "$LFS/boot"

# Extract sources into the target system at /usr/src/kernel-${KERNEL_VERSION}
SRC_DIR_TARGET="/usr/src/kernel-${KERNEL_VERSION}"
mkdir -p "$LFS$SRC_DIR_TARGET"
info "Extracting kernel into $LFS$SRC_DIR_TARGET"
tar -xf "$KERN_TARBALL" -C "$LFS$SRC_DIR_TARGET" --strip-components=1

cd "$LFS$SRC_DIR_TARGET"

# Apply our saved .config if present, otherwise generate a defconfig.
if [[ -f /project/configs/kernel/.config ]]; then
    info "Using saved kernel config from configs/kernel/.config"
    cp /project/configs/kernel/.config .config
else
    warn "No saved .config — using defconfig (you should customize via 'make menuconfig')"
    make defconfig
fi

# Enforce the localversion suffix demanded by the subject.
info "Setting CONFIG_LOCALVERSION=${KERNEL_LOCALVERSION}"
./scripts/config --set-str LOCALVERSION "${KERNEL_LOCALVERSION}"
./scripts/config --disable LOCALVERSION_AUTO
make olddefconfig

# Build kernel and modules.
info "Building kernel (this is the long one — go get coffee)"
make -j"$(nproc)" all

info "Installing kernel image and modules into the target system"
# We're not chrooted yet; install paths are relative to $LFS via INSTALL_*
make INSTALL_MOD_PATH="$LFS" modules_install
cp arch/x86/boot/bzImage "$LFS/boot/vmlinuz-${KERNEL_FULL}"
cp System.map            "$LFS/boot/System.map-${KERNEL_FULL}"
cp .config               "$LFS/boot/config-${KERNEL_FULL}"

# Persist the kernel config back into the repo so the build is reproducible.
mkdir -p /project/configs/kernel 2>/dev/null || true
cp .config /output/kernel.config.saved
info "Kernel config saved to /output/kernel.config.saved"
info "  → on the host, copy it into configs/kernel/.config to commit it"

info "Verifying expected paths"
test -f "$LFS/boot/vmlinuz-${KERNEL_FULL}" || die "Missing kernel binary"
test -d "$LFS$SRC_DIR_TARGET"              || die "Missing kernel sources in target"
info "  /boot/vmlinuz-${KERNEL_FULL}  ✓"
info "  ${SRC_DIR_TARGET}             ✓"

phase_end
