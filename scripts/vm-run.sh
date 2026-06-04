#!/bin/bash
# Boot the built disk image with QEMU on the host.
# Usage: vm-run.sh <image-path> [nographic|gui]

set -euo pipefail

IMG="${1:?usage: vm-run.sh <image> [nographic|gui]}"
MODE="${2:-nographic}"

[[ -f "$IMG" ]] || {
    echo "ERROR: image not found: $IMG" >&2
    exit 1
}
command -v qemu-system-x86_64 >/dev/null || {
    echo "ERROR: qemu-system-x86_64 not installed on host." >&2
    echo "Install it via your distro's package manager — this is the ONE host dep we allow." >&2
    exit 1
}

# Enable KVM if available.
KVM_ARGS=()
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    KVM_ARGS=(-enable-kvm -cpu host)
else
    echo "WARN: /dev/kvm not accessible, falling back to TCG (slow)." >&2
fi

QEMU_ARGS=(
    -m 2048
    -smp 2
    "${KVM_ARGS[@]}"
    -drive "file=${IMG},format=raw,if=virtio"
    -netdev "user,id=net0"
    -device "virtio-net-pci,netdev=net0"
    -boot c
)

case "$MODE" in
    nographic)
        QEMU_ARGS+=(-nographic -serial mon:stdio)
        ;;
    gui)
        QEMU_ARGS+=(-vga std)
        ;;
    *)
        echo "ERROR: unknown mode '$MODE' (want nographic|gui)" >&2
        exit 1
        ;;
esac

echo "==> qemu-system-x86_64 ${QEMU_ARGS[*]}"
exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
