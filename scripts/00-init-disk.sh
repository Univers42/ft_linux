#!/bin/bash
# Phase 0 — create and partition the disk image.
#
# Produces /output/ft_linux.img (20 GB raw) with:
#   p1  /boot   512 MB  ext4
#   p2  swap    2 GB
#   p3  /       remainder  ext4
#
# Re-entrant: if the image already exists with the expected layout, we skip.

. "$(dirname "$0")/lib.sh"

require_in_container
require_root
phase_start "00-init-disk"

# Detect what already exists so we can be re-entrant without lying.
need_create=1
need_format=1

if [[ -f "$IMG_PATH" ]]; then
    info "Image file exists at $IMG_PATH — checking state"
    need_create=0
    # Attach briefly to inspect partition state
    PROBE_LOOP="$(attach_image "$IMG_PATH")"
    if blkid "$(part "$PROBE_LOOP" 2)" 2>/dev/null | grep -q 'TYPE="ext4"' &&
        blkid "$(part "$PROBE_LOOP" 4)" 2>/dev/null | grep -q 'TYPE="ext4"'; then
        info "  partitions p2 and p4 already formatted as ext4"
        need_format=0
    else
        warn "  no ext4 filesystems found on p2/p4 — will reformat"
    fi
    detach_image "$PROBE_LOOP"
fi

if [[ "$need_create" -eq 1 ]]; then
    info "Creating ${IMG_SIZE_GB} GB sparse image at $IMG_PATH"
    truncate -s "${IMG_SIZE_GB}G" "$IMG_PATH"

    info "Partitioning (GPT, BIOS-boot + /boot + swap + /)"
    parted -s "$IMG_PATH" \
        mklabel gpt \
        mkpart bios_grub 1MiB 3MiB \
        set 1 bios_grub on \
        mkpart boot ext4 3MiB $((3 + PART_BOOT_MB))MiB \
        mkpart swap linux-swap $((3 + PART_BOOT_MB))MiB $((3 + PART_BOOT_MB + PART_SWAP_MB))MiB \
        mkpart root ext4 $((3 + PART_BOOT_MB + PART_SWAP_MB))MiB 100%
fi

if [[ "$need_format" -eq 1 ]]; then
    info "Attaching loop device"
    LOOP="$(attach_image "$IMG_PATH")"
    trap 'detach_image "$LOOP"' EXIT
    info "  loop: $LOOP"

    info "Formatting partitions"
    mkfs.ext4 -F -L boot "$(part "$LOOP" 2)"
    mkswap -L swap "$(part "$LOOP" 3)"
    mkfs.ext4 -F -L root "$(part "$LOOP" 4)"

    # Verify the filesystems are actually there
    info "Verifying"
    blkid "$(part "$LOOP" 2)" | grep -q 'TYPE="ext4"' || die "p2 not ext4 after mkfs"
    blkid "$(part "$LOOP" 4)" | grep -q 'TYPE="ext4"' || die "p4 not ext4 after mkfs"
    info "  p2 ext4 boot ✓"
    info "  p3 swap      ✓"
    info "  p4 ext4 root ✓"
fi

info "Disk image ready: $IMG_PATH"
phase_end
