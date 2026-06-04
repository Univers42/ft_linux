# Build functions for the LFS Ch. 5-6 cross-toolchain.
# Each build_* function follows the LFS book commands verbatim.
# Reference: https://www.linuxfromscratch.org/lfs/view/stable/chapter05/
#
# Everything here runs under `set -euo pipefail` (sourced via lib.sh), so a
# failing `cd` aborts the phase — SC2164's explicit `|| exit` is redundant.
# shellcheck disable=SC2164

# -- helpers used by every build_*  -----------------------------------------
unpack() {
    # unpack <url> → echoes the extracted source dir under $LFS/sources/
    local url="$1"
    local tarball
    tarball="$(fetch "$url")"
    local dir
    dir="$(extract "$tarball")"
    [[ -d "$dir" ]] || die "extract failed for $url"
    echo "$dir"
}

# ===========================================================================
# Chapter 5 — Cross-toolchain
# ===========================================================================

build_binutils_pass1() {
    local src
    src="$(unpack "$BINUTILS_URL")"
    with_clean_build "$src"
    ../configure --prefix="$LFS/tools" \
        --with-sysroot="$LFS" \
        --target="$LFS_TGT" \
        --disable-nls \
        --enable-gprofng=no \
        --disable-werror \
        --enable-default-hash-style=gnu
    make
    make install
    rm -rf "$src"
}

build_gcc_pass1() {
    local src
    src="$(unpack "$GCC_URL")"
    cd "$src"

    # GCC needs GMP, MPFR, MPC unpacked inside its source tree
    tar -xf "$(fetch "$MPFR_URL")"
    mv -v "mpfr-${MPFR_VERSION}" mpfr
    tar -xf "$(fetch "$GMP_URL")"
    mv -v "gmp-${GMP_VERSION}" gmp
    tar -xf "$(fetch "$MPC_URL")"
    mv -v "mpc-${MPC_VERSION}" mpc

    # Adjust default 64-bit lib dir
    case "$(uname -m)" in
        x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
    esac

    with_clean_build "$src"
    ../configure \
        --target="$LFS_TGT" \
        --prefix="$LFS/tools" \
        --with-glibc-version="${GLIBC_VERSION}" \
        --with-sysroot="$LFS" \
        --with-newlib \
        --without-headers \
        --enable-default-pie \
        --enable-default-ssp \
        --disable-nls \
        --disable-shared \
        --disable-multilib \
        --disable-threads \
        --disable-libatomic \
        --disable-libgomp \
        --disable-libquadmath \
        --disable-libssp \
        --disable-libvtv \
        --disable-libstdcxx \
        --enable-languages=c,c++
    make
    make install

    # The book's "limits.h" rebuild trick — needed for glibc-build later
    cd "$src"
    cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
        "$(dirname "$("$LFS/tools/bin/$LFS_TGT-gcc" -print-libgcc-file-name)")/include/limits.h"

    rm -rf "$src"
}

build_linux_headers() {
    # Use OUR kernel (6.6.32-dlesieur) for the headers in glibc.
    local kern_url="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"
    local tarball
    tarball="$(fetch "$kern_url")"
    rm -rf "$LFS/sources/linux-${KERNEL_VERSION}"
    tar -xf "$tarball" -C "$LFS/sources"
    cd "$LFS/sources/linux-${KERNEL_VERSION}"
    make mrproper
    make headers
    find usr/include -type f ! -name '*.h' -delete
    cp -rv usr/include "$LFS/usr"
    cd "$LFS/sources"
    rm -rf "linux-${KERNEL_VERSION}"
}

build_glibc() {
    local src
    src="$(unpack "$GLIBC_URL")"
    cd "$src"

    # Build symlinks the book asks for
    case "$(uname -m)" in
        x86_64)
            ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64"
            ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
            ;;
    esac

    # FHS-compliance patch (per book)
    if [[ -f /project/patches/glibc-${GLIBC_VERSION}-fhs-1.patch ]]; then
        patch -Np1 -i "/project/patches/glibc-${GLIBC_VERSION}-fhs-1.patch"
    fi

    with_clean_build "$src"
    echo "rootsbindir=/usr/sbin" >configparms
    ../configure \
        --prefix=/usr \
        --host="$LFS_TGT" \
        --build="$(../scripts/config.guess)" \
        --enable-kernel=4.19 \
        --with-headers="$LFS/usr/include" \
        --disable-nscd \
        libc_cv_slibdir=/usr/lib
    make
    make DESTDIR="$LFS" install
    # Fix a hard-coded path
    sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"

    # Quick sanity check
    echo 'int main(){}' | "$LFS/tools/bin/$LFS_TGT-gcc" -xc - -o /tmp/dummy
    readelf -l /tmp/dummy | grep ld-linux || die "glibc sanity check failed"
    rm /tmp/dummy

    rm -rf "$src"
}

build_libstdcxx() {
    # Built from GCC sources, after glibc is in place
    local src
    src="$(unpack "$GCC_URL")"
    with_clean_build "$src"
    ../libstdc++-v3/configure \
        --host="$LFS_TGT" \
        --build="$(../config.guess)" \
        --prefix=/usr \
        --disable-multilib \
        --disable-nls \
        --disable-libstdcxx-pch \
        --with-gxx-include-dir="/tools/$LFS_TGT/include/c++/${GCC_VERSION}"
    make
    make DESTDIR="$LFS" install
    rm -v "$LFS"/usr/lib/lib{stdc++{,exp,fs},supc++}.la
    rm -rf "$src"
}

# ===========================================================================
# Chapter 6 — Cross-compile temporary tools
# ===========================================================================
# These are all "cross-compile, DESTDIR=$LFS install" with package-specific
# configure flags. Pattern is consistent.

_cross_install() {
    # _cross_install <configure-args...>
    ../configure --host="$LFS_TGT" --build="$(../build-aux/config.guess 2>/dev/null || ../config.guess)" "$@"
    make
    make DESTDIR="$LFS" install
}

build_m4() {
    local src
    src="$(unpack "$M4_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr
    rm -rf "$src"
}

build_ncurses() {
    local src
    src="$(unpack "$NCURSES_URL")"
    cd "$src"
    sed -i s/mawk// configure
    mkdir -p build
    pushd build
    ../configure
    make -C include
    make -C progs tic
    popd
    # Cross-build in $src itself (NOT a fresh build/, which would delete the
    # host tic we just built and is needed by TIC_PATH below).
    ./configure --prefix=/usr \
        --host="$LFS_TGT" \
        --build="$(./config.guess)" \
        --mandir=/usr/share/man \
        --with-manpage-format=normal \
        --with-shared \
        --without-normal \
        --with-cxx-shared \
        --without-debug \
        --without-ada \
        --disable-stripping \
        --enable-widec
    make
    make DESTDIR="$LFS" TIC_PATH="$(pwd)/build/progs/tic" install
    ln -sfv libncursesw.so "$LFS/usr/lib/libncurses.so"
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$LFS/usr/include/curses.h"
    rm -rf "$src"
}

build_bash() {
    local src
    src="$(unpack "$BASH_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr \
        --without-bash-malloc \
        bash_cv_strtold_broken=no
    ln -sv bash "$LFS/usr/bin/sh"
    rm -rf "$src"
}

build_coreutils() {
    local src
    src="$(unpack "$COREUTILS_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr \
        --enable-install-program=hostname \
        --enable-no-install-program=kill,uptime
    mkdir -pv "$LFS/usr/share/man/man8"
    mv -v "$LFS/usr/share/man/man1/chroot.1" "$LFS/usr/share/man/man8/chroot.8" || true
    sed -i 's/"1"/"8"/' "$LFS/usr/share/man/man8/chroot.8" 2>/dev/null || true
    rm -rf "$src"
}

build_diffutils() {
    local src
    src="$(unpack "$DIFFUTILS_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr
    rm -rf "$src"
}

build_file() {
    local src
    src="$(unpack "$FILE_URL")"
    cd "$src"
    # file needs a host-built copy first
    mkdir -p build
    pushd build
    ../configure --disable-bzlib \
        --disable-libseccomp \
        --disable-xzlib \
        --disable-zlib
    make
    popd
    # Cross-build in $src (NOT a fresh build/, which would delete the host
    # `file` that FILE_COMPILE below needs).
    ./configure --prefix=/usr --host="$LFS_TGT" --build="$(./config.guess)"
    make FILE_COMPILE="$(pwd)/build/src/file"
    make DESTDIR="$LFS" install
    rm -v "$LFS/usr/lib/libmagic.la"
    rm -rf "$src"
}

build_findutils() {
    local src
    src="$(unpack "$FINDUTILS_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr \
        --localstatedir=/var/lib/locate
    rm -rf "$src"
}

build_gawk() {
    local src
    src="$(unpack "$GAWK_URL")"
    cd "$src"
    sed -i 's/extras//' Makefile.in
    with_clean_build "$src"
    _cross_install --prefix=/usr
    rm -rf "$src"
}

build_grep() {
    local src
    src="$(unpack "$GREP_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr
    rm -rf "$src"
}

build_gzip() {
    local src
    src="$(unpack "$GZIP_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr --host="$LFS_TGT"
    make
    make DESTDIR="$LFS" install
    rm -rf "$src"
}

build_make() {
    local src
    src="$(unpack "$MAKE_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr \
        --without-guile
    rm -rf "$src"
}

build_patch() {
    local src
    src="$(unpack "$PATCH_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr
    rm -rf "$src"
}

build_sed() {
    local src
    src="$(unpack "$SED_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr
    rm -rf "$src"
}

build_tar() {
    local src
    src="$(unpack "$TAR_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr
    rm -rf "$src"
}

build_xz() {
    local src
    src="$(unpack "$XZ_URL")"
    with_clean_build "$src"
    _cross_install --prefix=/usr \
        --disable-static \
        --docdir="/usr/share/doc/xz-${XZ_VERSION}"
    rm -v "$LFS/usr/lib/liblzma.la"
    rm -rf "$src"
}

build_binutils_pass2() {
    local src
    src="$(unpack "$BINUTILS_URL")"
    cd "$src"
    # shellcheck disable=SC2016  # $add_dir is literal in the sed program (per LFS)
    sed '6009s/$add_dir//' -i ltmain.sh
    with_clean_build "$src"
    ../configure \
        --prefix=/usr \
        --build="$(../config.guess)" \
        --host="$LFS_TGT" \
        --disable-nls \
        --enable-shared \
        --enable-gprofng=no \
        --disable-werror \
        --enable-64-bit-bfd \
        --enable-default-hash-style=gnu
    make
    make DESTDIR="$LFS" install
    rm -v "$LFS"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
    rm -rf "$src"
}

build_gcc_pass2() {
    local src
    src="$(unpack "$GCC_URL")"
    cd "$src"
    tar -xf "$(fetch "$MPFR_URL")"
    mv -v "mpfr-${MPFR_VERSION}" mpfr
    tar -xf "$(fetch "$GMP_URL")"
    mv -v "gmp-${GMP_VERSION}" gmp
    tar -xf "$(fetch "$MPC_URL")"
    mv -v "mpc-${MPC_VERSION}" mpc

    case "$(uname -m)" in
        x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
    esac

    sed '/thread_header =/s/@.*@/gthr-posix.h/' -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in

    with_clean_build "$src"
    ../configure \
        --build="$(../config.guess)" \
        --host="$LFS_TGT" \
        --target="$LFS_TGT" \
        LDFLAGS_FOR_TARGET=-L"$PWD/$LFS_TGT/libgcc" \
        --prefix=/usr \
        --with-build-sysroot="$LFS" \
        --enable-default-pie \
        --enable-default-ssp \
        --disable-nls \
        --disable-multilib \
        --disable-libatomic \
        --disable-libgomp \
        --disable-libquadmath \
        --disable-libsanitizer \
        --disable-libssp \
        --disable-libvtv \
        --enable-languages=c,c++
    make
    make DESTDIR="$LFS" install
    ln -sv gcc "$LFS/usr/bin/cc"
    rm -rf "$src"
}
