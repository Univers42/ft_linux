#!/bin/bash
# Phase 2 — Build the final system inside a chroot (LFS Ch. 7-8).
#
# Prepares the chroot (virtual FS, skeleton, essential files), stages hellish
# + its runtime libs + the static watchdog into the chroot so the in-chroot
# userland build ALSO runs under our shell, then runs /sources/scripts/
# build-all.sh under hellish. Re-entrant: per-package stamps live in the image.

. "$(dirname "$0")/lib.sh"

require_in_container
require_root
phase_start "02-build-system"

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

info "Attaching disk image"
LOOP="$(attach_image "$IMG_PATH")"
arm_cleanup "$LOOP"
sleep 1

mkdir -p "$LFS"
umount -R "$LFS" 2>/dev/null || true
mount "$(part "$LOOP" 4)" "$LFS"
mkdir -p "$LFS/boot"
mount "$(part "$LOOP" 2)" "$LFS/boot"

# -- Virtual kernel filesystems (LFS 7.3) -----------------------------------
prepare_virtfs() {
    mkdir -p "$LFS"/dev "$LFS"/proc "$LFS"/sys "$LFS"/run
    mountpoint -q "$LFS/dev" || mount --bind /dev "$LFS/dev"
    mkdir -p "$LFS/dev/pts"
    mountpoint -q "$LFS/dev/pts" || mount -t devpts devpts -o gid=5,mode=620 "$LFS/dev/pts"
    mountpoint -q "$LFS/proc" || mount -t proc proc "$LFS/proc"
    mountpoint -q "$LFS/sys" || mount -t sysfs sysfs "$LFS/sys"
    mountpoint -q "$LFS/run" || mount -t tmpfs tmpfs "$LFS/run"
    mknod -m 600 "$LFS/dev/console" c 5 1 2>/dev/null || true
    mknod -m 666 "$LFS/dev/null" c 1 3 2>/dev/null || true
}

# -- Directory skeleton + essential files (LFS 7.5, 7.6) --------------------
prepare_skeleton() {
    mkdir -p "$LFS"/home "$LFS"/mnt "$LFS"/opt "$LFS"/srv
    mkdir -p "$LFS"/etc/opt "$LFS"/etc/sysconfig
    mkdir -p "$LFS"/media/floppy "$LFS"/media/cdrom
    mkdir -p "$LFS"/usr/local/bin "$LFS"/usr/local/lib "$LFS"/usr/local/sbin
    mkdir -p "$LFS"/usr/include "$LFS"/usr/src
    mkdir -p "$LFS"/usr/share/man/man1 "$LFS"/usr/share/man/man2 \
        "$LFS"/usr/share/man/man3 "$LFS"/usr/share/man/man4 \
        "$LFS"/usr/share/man/man5 "$LFS"/usr/share/man/man6 \
        "$LFS"/usr/share/man/man7 "$LFS"/usr/share/man/man8
    mkdir -p "$LFS"/var/cache "$LFS"/var/local "$LFS"/var/log \
        "$LFS"/var/mail "$LFS"/var/opt "$LFS"/var/spool
    mkdir -p "$LFS"/var/lib/color "$LFS"/var/lib/misc "$LFS"/var/lib/locate
    ln -sfn /run "$LFS/var/run"
    ln -sfn /run/lock "$LFS/var/lock"
    install -d -m 0750 "$LFS/root"
    install -d -m 1777 "$LFS/tmp" "$LFS/var/tmp"
    write_etc_files
}

write_etc_files() {
    cat >"$LFS/etc/passwd" <<"EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF
    cat >"$LFS/etc/group" <<"EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF
    printf '127.0.0.1 localhost %s\n::1 localhost\n' "$HOSTNAME_TARGET" >"$LFS/etc/hosts"
    : >"$LFS/var/log/btmp"
    : >"$LFS/var/log/lastlog"
    : >"$LFS/var/log/faillog"
    : >"$LFS/var/log/wtmp"
    chmod 600 "$LFS/var/log/btmp"
    chmod 664 "$LFS/var/log/lastlog"
}

# -- Stage hellish + libs + watchdog + build scripts into the chroot --------
stage_hellish() {
    install -d "$LFS/tools/bin" "$LFS/tools/lib" "$LFS/sources/scripts"
    install -m 755 /usr/local/bin/hellish "$LFS/tools/bin/hellish"
    local l
    for l in libreadline.so libtinfo.so; do
        cp -av /lib/x86_64-linux-gnu/"$l"* "$LFS/tools/lib/" 2>/dev/null || \
            cp -av /usr/lib/x86_64-linux-gnu/"$l"* "$LFS/tools/lib/" 2>/dev/null || true
    done
    if [ -x /output/bin/watchdog ]; then
        install -m 755 /output/bin/watchdog "$LFS/tools/bin/watchdog"
    fi
    install -m 644 "$SCRIPTS_DIR/packages.sh" "$LFS/sources/scripts/packages.sh"
    for f in chroot-lib.sh build-system-lib.sh build-all.sh; do
        [ -f "$SCRIPTS_DIR/$f" ] && install -m 644 "$SCRIPTS_DIR/$f" "$LFS/sources/scripts/$f"
    done
}

CHROOT_ENV='HOME=/root TERM=xterm PATH=/usr/bin:/usr/sbin:/tools/bin LD_LIBRARY_PATH=/tools/lib'

chroot_hellish() {
    # chroot_hellish <args...> — run hellish inside the chroot with a clean env.
    # shellcheck disable=SC2086
    chroot "$LFS" /usr/bin/env -i $CHROOT_ENV MAKEFLAGS="${MAKEFLAGS:-}" \
        /tools/bin/hellish "$@"
}

step "07-prepare-virtfs" prepare_virtfs
step "07-prepare-skeleton" prepare_skeleton
stage_hellish

info "Smoke test: hellish inside the chroot"
# shellcheck disable=SC2016  # snippet must be evaluated by hellish, not here
if chroot_hellish -c 'echo HELLISH_IN_CHROOT_OK; for i in a b; do echo "$i"; done'; then
    info "[ok] hellish runs in the chroot"
else
    die "hellish failed to run in the chroot — check /tools/lib staging"
fi

if [ -f "$LFS/sources/scripts/build-all.sh" ]; then
    info "Running Ch.8 build-all under hellish in the chroot"
    chroot_hellish /sources/scripts/build-all.sh
else
    warn "build-all.sh not present yet — chroot prepared + hellish staged."
    warn "Add scripts/build-system-lib.sh + scripts/build-all.sh to build Ch.8."
fi

phase_end
