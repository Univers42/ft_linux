#!/bin/bash
# In-chroot LFS Ch.8 driver. Run under hellish inside the chroot:
#   hellish /sources/scripts/build-all.sh
# Builds each Ch.8 package (LFS 12.1) in book order. Each package runs in its
# own watchdog-guarded hellish (stall/timeout kill + isolation), and is stamped
# so re-runs resume. Order is derived from build-system-lib.sh (= book order).
set -euo pipefail

SS=/sources/scripts
. "$SS/chroot-lib.sh"
. "$SS/packages.sh"
. "$SS/build-system-lib.sh"

ORDER="$(grep -oE '^build_[a-z0-9_]+' "$SS/build-system-lib.sh" | sed 's/^build_//')"
IDLE="${IDLE:-1800}"
PKG_T="${PKG_T:-10800}"

for pkg in $ORDER; do
    if is_done "$pkg"; then
        info "[skip] ch8-$pkg"
        continue
    fi
    info ""
    info "===== ch8-$pkg ====="
    guard "$IDLE" "$PKG_T" /tools/bin/hellish -c \
        ". $SS/chroot-lib.sh; . $SS/packages.sh; . $SS/build-system-lib.sh; build_$pkg"
    stamp_done "$pkg"
    info "[done] ch8-$pkg"
done
info ""
info "Ch.8 build-all complete."
