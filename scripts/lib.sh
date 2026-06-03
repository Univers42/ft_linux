#!/bin/bash
# Shared helpers, constants, and logging for all phase scripts.
# Source this from each phase: `. "$(dirname "$0")/lib.sh"`

set -euo pipefail

# -- Subject constants -------------------------------------------------------
STUDENT_LOGIN="${STUDENT_LOGIN:-dlesieur}"
KERNEL_VERSION="${KERNEL_VERSION:-6.6.32}"
KERNEL_LOCALVERSION="-${STUDENT_LOGIN}"
KERNEL_FULL="${KERNEL_VERSION}${KERNEL_LOCALVERSION}"
HOSTNAME_TARGET="${STUDENT_LOGIN}"

# -- LFS paths (inside the container) ---------------------------------------
LFS="${LFS:-/mnt/lfs}"
LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"

# -- Image layout ------------------------------------------------------------
IMG_PATH="${IMG_PATH:-/output/ft_linux.img}"
IMG_SIZE_GB="${IMG_SIZE_GB:-20}"
PART_BOOT_MB=512
PART_SWAP_MB=2048

# -- Output paths ------------------------------------------------------------
LOG_DIR=/output/logs
mkdir -p "$LOG_DIR"

# -- Logging -----------------------------------------------------------------
_phase_name=""
phase_start() {
    _phase_name="$1"
    local stamp; stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "============================================================"
    echo "  PHASE: $_phase_name"
    echo "  start: $stamp"
    echo "============================================================"
    exec > >(tee -a "$LOG_DIR/${_phase_name}.log") 2>&1
}

phase_end() {
    local stamp; stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "------------------------------------------------------------"
    echo "  PHASE DONE: $_phase_name   end: $stamp"
    echo "------------------------------------------------------------"
}

info()  { echo "[i] $*"; }
warn()  { echo "[!] $*" >&2; }
die()   { echo "[x] $*" >&2; exit 1; }

# -- Guards ------------------------------------------------------------------
require_in_container() {
    [[ -f /.dockerenv ]] || die "This script must run inside the build container. Use 'make phase-...'."
}

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "Need root inside the container."
}

# -- Loop device helpers -----------------------------------------------------
# Inside Docker there's no udev, so `losetup --partscan` won't create the
# /dev/loopXpN nodes. We use kpartx (device-mapper) instead — it creates
# /dev/mapper/loopXpN nodes that work without udev.
#
# After attach_image, use $(part "$LOOP" N) to get the device path for
# partition N. Example:  mount "$(part "$LOOP" 4)" "$LFS"
attach_image() {
    local img="$1"
    local loop
    loop="$(losetup --find --show "$img")"
    # kpartx -a: add mappings; -s: sync (wait for them to appear)
    kpartx -as "$loop" >/dev/null
    # Be defensive — give the device-mapper a moment on slow hosts.
    local n="$(basename "$loop")"
    for _ in 1 2 3 4 5; do
        [[ -b "/dev/mapper/${n}p1" ]] && break
        sleep 0.5
    done
    echo "$loop"
}

part() {
    # part <loop-device> <partition-number>  →  /dev/mapper/loopXpN
    local loop="$1" n="$2"
    echo "/dev/mapper/$(basename "$loop")p${n}"
}

detach_image() {
    local loop="$1"
    sync
    kpartx -d "$loop" 2>/dev/null || true
    losetup -d "$loop" 2>/dev/null || true
}

# -- Source tarball helpers --------------------------------------------------
# Sources are cached in /output/sources so re-runs don't redownload.
SRC_CACHE=/output/sources

fetch() {
    # fetch <url> [filename]
    # Downloads to $SRC_CACHE if not already there. Idempotent.
    local url="$1"
    local out="${2:-$(basename "$url")}"
    local path="$SRC_CACHE/$out"
    mkdir -p "$SRC_CACHE"
    if [[ -f "$path" ]]; then
        info "  cached: $out"
    else
        info "  fetching: $url"
        curl -fL --retry 3 --retry-delay 2 -o "$path.tmp" "$url"
        mv "$path.tmp" "$path"
    fi
    echo "$path"
}

extract() {
    # extract <tarball> [dest-dir]
    # Extracts into $LFS/sources/<package-name>/ by default.
    # Echoes the resulting directory path.
    local tarball="$1"
    local dest="${2:-$LFS/sources}"
    mkdir -p "$dest"
    local before; before="$(ls "$dest" 2>/dev/null)"
    tar -xf "$tarball" -C "$dest"
    local after;  after="$(ls "$dest" 2>/dev/null)"
    # The newly created directory is whatever's in "after" but not "before".
    comm -13 <(echo "$before" | sort) <(echo "$after" | sort) | head -1 | \
        xargs -I{} echo "$dest/{}"
}

with_clean_build() {
    # with_clean_build <source-dir>  →  enters $source-dir/build (fresh).
    local src="$1"
    rm -rf "$src/build"
    mkdir -p "$src/build"
    cd "$src/build"
}

stamp_done() {
    # mark a build step as done so re-runs skip it
    mkdir -p "$LFS/.stamps"
    touch "$LFS/.stamps/$1"
}

is_done() {
    [[ -f "$LFS/.stamps/$1" ]]
}

step() {
    # step <name> <build-function-name>
    local name="$1" fn="$2"
    if is_done "$name"; then
        info "[skip] $name (already done)"
        return 0
    fi
    info ""
    info "===== $name ====="
    "$fn"
    stamp_done "$name"
    info "[done] $name"
}
