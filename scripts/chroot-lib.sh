#!/bin/bash
# Helpers for the in-chroot Ch.8 build (sourced by build-all.sh, run under
# hellish inside the chroot). Sources + patches are pre-staged in /sources by
# the outside driver (02-build-system.sh) — there is NO network here, so fetch
# does not download; it just resolves the staged path.
set -euo pipefail

SRC_DIR=/sources
STAMPS=/sources/.stamps

info() { echo "[i] $*" >&2; }
warn() { echo "[!] $*" >&2; }
die() {
    echo "[x] $*" >&2
    exit 1
}

# Resource-aware -j (caps RAM-hungry builds; same heuristic as lib.sh).
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

# fetch <url> — the tarball is already in /sources; echo its path (no download).
fetch() {
    echo "$SRC_DIR/$(basename "$1")"
}

# unpack <url> — extract the pre-staged tarball into /sources, echo its dir.
unpack() {
    local tb top
    tb="$SRC_DIR/$(basename "$1")"
    [ -f "$tb" ] || die "missing pre-staged source: $tb"
    top="$(tar -tf "$tb" 2>/dev/null | head -1 | cut -d/ -f1)"
    [ -n "$top" ] || die "cannot read $tb"
    rm -rf "${SRC_DIR:?}/$top"
    tar -xf "$tb" -C "$SRC_DIR"
    echo "$SRC_DIR/$top"
}

with_clean_build() {
    local src="$1"
    rm -rf "$src/build"
    mkdir -p "$src/build"
    cd "$src/build"
}

is_done() { [ -f "$STAMPS/$1" ]; }
stamp_done() {
    mkdir -p "$STAMPS"
    touch "$STAMPS/$1"
}

# guard <idle_s> <total_s> <cmd...> — run under the watchdog (kills the whole
# process group on stall/timeout), or directly if the binary is absent.
WATCHDOG="${WATCHDOG:-/tools/bin/watchdog}"
guard() {
    local idle="$1" total="$2"
    shift 2
    if [ -x "$WATCHDOG" ]; then
        "$WATCHDOG" -i "$idle" -t "$total" -- "$@"
    else
        "$@"
    fi
}
