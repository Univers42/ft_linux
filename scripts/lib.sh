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
# Inside Docker there's no udev, so `losetup -P` (partition scan) populates
# /sys/block/loopX/loopXpN/dev but never creates the /dev/loopXpN device nodes.
# We previously used kpartx (device-mapper, /dev/mapper/loopXpN), but grub-probe
# mis-classifies a device-mapper node as an LVM volume and grub-install fails
# ("disk 'lvm/loopXpN' not found"). So instead we partition-scan with
# `losetup -P` and mknod the REAL kernel partition nodes /dev/loopXpN ourselves
# from the major:minor in sysfs — grub-probe handles those as plain (hd0,gptN)
# partitions, and they mount exactly like the kpartx nodes did.
#
# After attach_image, use $(part "$LOOP" N) to get the device path for
# partition N. Example:  mount "$(part "$LOOP" 4)" "$LFS"
attach_image() {
    local img="$1"
    local loop n pd pp dm
    loop="$(losetup -P --find --show "$img")"
    n="$(basename "$loop")"
    # Wait for the kernel to expose the partition entries in sysfs, then mknod
    # the matching /dev nodes (no udev in Docker to do it for us).
    local i
    for i in 1 2 3 4 5; do
        if [ -e "/sys/block/${n}/${n}p1/dev" ]; then
            break
        fi
        sleep 0.5
    done
    for pd in "/sys/block/${n}/${n}"p*; do
        [ -d "$pd" ] || continue
        pp="$(basename "$pd")"
        dm="$(cat "$pd/dev")"
        if [ ! -b "/dev/$pp" ]; then
            mknod "/dev/$pp" b "${dm%%:*}" "${dm##*:}"
        fi
    done
    echo "$loop"
}

part() {
    # part <loop-device> <partition-number>  →  /dev/loopXpN
    local loop="$1" n="$2"
    echo "/dev/$(basename "$loop")p${n}"
}

detach_image() {
    local loop="$1"
    local n pp
    sync
    n="$(basename "$loop")"
    # Remove the partition nodes we created (the kernel/loop teardown won't, and
    # a stale node aliasing a re-attached loop would be a footgun).
    for pp in "/dev/${n}"p*; do
        if [ -b "$pp" ]; then
            rm -f "$pp"
        fi
    done
    losetup -d "$loop" 2>/dev/null || true
}

# -- Teardown on exit AND on signals -----------------------------------------
# hellish does NOT run the EXIT trap on SIGTERM (verified), so a watchdog or
# host-timeout kill would leak the loop device + mounts. Register TERM/INT
# explicitly. _teardown is idempotent, so the TERM-then-EXIT double fire is safe.
LFS_LOOP=""
_teardown() {
    umount -R "$LFS" 2>/dev/null || true
    if [ -n "$LFS_LOOP" ]; then
        detach_image "$LFS_LOOP" 2>/dev/null || true
    fi
}
arm_cleanup() {
    LFS_LOOP="$1"
    trap '_teardown' EXIT
    trap '_teardown; exit 143' TERM
    trap '_teardown; exit 130' INT
}

# finish_clean: deterministic teardown for the SUCCESS path.
# hellish does not fire the EXIT trap when `exec > >(tee …)` is active (verified:
# the redirection from phase_start swallows it), so on a clean run the loop would
# leak until `make loopclean`. Call this explicitly at the end of a phase, right
# before phase_end, to unwind mounts + detach the loop now. We also clear the
# EXIT trap so bash (which *does* fire it) doesn't run _teardown a second time.
# The TERM/INT traps stay armed as the safety net for the kill paths.
# _teardown is idempotent, so a stray double-fire is harmless either way.
finish_clean() {
    _teardown
    trap - EXIT
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
