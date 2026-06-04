#!/bin/bash
# Autonomous boot verification — host-side, like vm-run.sh.
# Boots the image headless in QEMU, waits for the SysVinit login prompt on the
# serial console, logs in as root (passwordless), runs the subject-criteria
# checks, powers off, and saves the full serial log for inspection.
#
# Usage: vm-verify.sh <image> [logfile]
set -uo pipefail

IMG="${1:?usage: vm-verify.sh <image> [logfile]}"
OUT="${2:-/tmp/ft_linux-boot.log}"

command -v qemu-system-x86_64 >/dev/null || {
    echo "ERROR: qemu-system-x86_64 not on host" >&2
    exit 1
}

QIN="$(mktemp -u)"
mkfifo "$QIN"
: >"$OUT"

KVM=()
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM=(-enable-kvm -cpu host)
fi

# Input driver: wait for the actual "login:" prompt (robust to boot speed),
# then log in and run the checks. Markers bracket the command output so the
# grep in the caller is unambiguous.
(
    for _ in $(seq 1 140); do
        grep -qE 'login:' "$OUT" 2>/dev/null && break
        sleep 1
    done
    sleep 2
    printf 'root\n'
    sleep 4
    printf '%s\n' 'echo FTV_BEGIN; echo "UNAME=$(uname -r)"; echo "HOST=$(hostname)"; echo "PARTS=$(lsblk -no NAME 2>/dev/null | wc -l)"; echo "MOUNTS=$(grep -c LABEL /etc/fstab)"; wget -q -T 8 -O /tmp/w http://example.com/ 2>/dev/null && echo "NET=OK($(wc -c </tmp/w)b)" || echo "NET=FAIL"; echo "BASH=$(bash --version | head -1)"; echo FTV_END'
    sleep 10
    printf 'poweroff\n'
    sleep 18
) >"$QIN" &
WPID=$!

timeout 200 qemu-system-x86_64 \
    -m 2048 -smp 2 "${KVM[@]}" \
    -drive "file=${IMG},format=raw,if=virtio" \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    -display none -serial stdio <"$QIN" >>"$OUT" 2>&1

kill "$WPID" 2>/dev/null || true
rm -f "$QIN"
echo "=== boot log: $OUT ($(wc -l <"$OUT") lines) ==="
