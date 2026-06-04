#!/bin/bash
# Shared helpers, constants, and logging for all phase scripts.
# Source this from each phase: `. "$(dirname "$0")/lib.sh"`
#
# Constants here (KERNEL_FULL, HOSTNAME_TARGET, PART_*) are consumed by the
# sourcing phase scripts, so ShellCheck can't see their use from this file.
# shellcheck disable=SC2034

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

# -- Parallelism (resource-aware) -------------------------------------------
# compute_jobs: min(nproc, MemAvailableGB/2). Caps `make -j` so the RAM-hungry
# builds (gcc, glibc, binutils) can't OOM the host. Set at runtime here because
# docker-compose cannot expand $(nproc) in its environment block.
compute_jobs() {
    local cpus mem_kb mem_gb half
    cpus="$(nproc 2>/dev/null || echo 1)"
    mem_kb="$(awk '/^MemAvailable:/{print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
    mem_gb=$((mem_kb / 1024 / 1024))
    half=$((mem_gb / 2))
    if [ "$half" -lt 1 ]; then half=1; fi
    if [ "$cpus" -lt "$half" ]; then echo "$cpus"; else echo "$half"; fi
}
JOBS="${JOBS:-$(compute_jobs)}"
export MAKEFLAGS="-j${JOBS}"

# -- Watchdog (timeouts on long/risky steps; src in tools/watchdog) ----------
# guard <idle_s> <total_s> <cmd...> — run under the watchdog (kills the whole
# process group on stall/total timeout), or directly if the binary is absent.
WATCHDOG="${WATCHDOG:-/output/bin/watchdog}"
guard() {
    local idle="$1" total="$2"
    shift 2
    if [ -x "$WATCHDOG" ]; then
        "$WATCHDOG" -i "$idle" -t "$total" -- "$@"
    else
        "$@"
    fi
}

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
    local stamp
    stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "============================================================"
    echo "  PHASE: $_phase_name"
    echo "  start: $stamp"
    echo "============================================================"
    exec > >(tee -a "$LOG_DIR/${_phase_name}.log") 2>&1
}

phase_end() {
    local stamp
    stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "------------------------------------------------------------"
    echo "  PHASE DONE: $_phase_name   end: $stamp"
    echo "------------------------------------------------------------"
}

info() { echo "[i] $*" >&2; }
warn() { echo "[!] $*" >&2; }
die() {
    echo "[x] $*" >&2
    exit 1
}

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
    local n
    n="$(basename "$loop")"
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
    # extract <tarball> [dest-dir]; echoes the extracted top-level dir path.
    # Idempotent + reliable: derive the dir name from the tarball itself
    # (not a before/after ls diff, which breaks when a prior run left the dir
    # behind) and clear any stale copy before extracting.
    local tarball="$1"
    local dest="${2:-$LFS/sources}"
    local top
    mkdir -p "$dest"
    top="$(tar -tf "$tarball" 2>/dev/null | head -1 | cut -d/ -f1)"
    [ -n "$top" ] || return 1
    rm -rf "${dest:?}/$top"
    tar -xf "$tarball" -C "$dest"
    echo "$dest/$top"
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
