# Build functions for the LFS Ch. 8 final system (native build inside chroot).
# Each build_* function follows the LFS 12.1 book commands verbatim.
# Reference: https://www.linuxfromscratch.org/lfs/view/12.1/chapter08/
#
# KEY DIFFERENCE from build-toolchain-lib.sh: these run INSIDE the chroot with
# the native compiler — no --host=/--build=/cross flags, no DESTDIR=$LFS.
# unpack() / with_clean_build() / fetch() / die() all come from lib.sh.
# shellcheck disable=SC2164

# ===========================================================================
# Chapter 8 — Final system packages (native, chroot)
# LFS 12.1 order: man-pages → iana-etc → glibc → zlib → bzip2 → xz → zstd
#   → file → readline → m4 → bc → flex → tcl → expect → dejagnu → pkgconf
#   → binutils → gmp → mpfr → mpc → attr → acl → libcap → libxcrypt
#   → shadow → gcc
# ===========================================================================

build_man_pages() {
    local src
    src="$(unpack "$MAN_PAGES_URL")"
    cd "$src"
    # Remove crypt man pages — provided by libxcrypt
    rm -v man3/crypt*
    make prefix=/usr install
    rm -rf "$src"
}

build_iana_etc() {
    local src
    src="$(unpack "$IANA_ETC_URL")"
    cd "$src"
    cp services protocols /etc
    rm -rf "$src"
}

build_glibc() {
    local src
    src="$(unpack "$GLIBC_URL")"
    cd "$src"

    # Apply the FHS-compliance patch (LFS 12.1 patch for glibc-2.39)
    patch -Np1 -i "../glibc-${GLIBC_VERSION}-fhs-1.patch"

    # NOTE: glibc 2.39 does NOT need the abort.c fixup — that is a 2.42+ issue.

    mkdir -v build
    cd build
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure --prefix=/usr \
                 --disable-werror \
                 --enable-kernel=4.19 \
                 --enable-stack-protector=strong \
                 --disable-nscd \
                 libc_cv_slibdir=/usr/lib
    make
    make check || true

    # Pre-install: ensure ld.so.conf exists; suppress the test-installation step
    touch /etc/ld.so.conf
    # shellcheck disable=SC2016  # $(PERL) is a Makefile variable, not a shell expansion
    sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile

    make install
    sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd

    # -- Locales ----------------------------------------------------------------
    mkdir -pv /usr/lib/locale
    localedef -i C -f UTF-8 C.UTF-8
    localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
    localedef -i de_DE -f ISO-8859-1 de_DE
    localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
    localedef -i de_DE -f UTF-8 de_DE.UTF-8
    localedef -i el_GR -f ISO-8859-7 el_GR
    localedef -i en_GB -f ISO-8859-1 en_GB
    localedef -i en_GB -f UTF-8 en_GB.UTF-8
    localedef -i en_HK -f ISO-8859-1 en_HK
    localedef -i en_PH -f ISO-8859-1 en_PH
    localedef -i en_US -f ISO-8859-1 en_US
    localedef -i en_US -f UTF-8 en_US.UTF-8
    localedef -i es_ES -f ISO-8859-15 es_ES@euro
    localedef -i es_MX -f ISO-8859-1 es_MX
    localedef -i fa_IR -f UTF-8 fa_IR
    localedef -i fr_FR -f ISO-8859-1 fr_FR
    localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
    localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
    localedef -i is_IS -f ISO-8859-1 is_IS
    localedef -i is_IS -f UTF-8 is_IS.UTF-8
    localedef -i it_IT -f ISO-8859-1 it_IT
    localedef -i it_IT -f ISO-8859-15 it_IT@euro
    localedef -i it_IT -f UTF-8 it_IT.UTF-8
    localedef -i ja_JP -f EUC-JP ja_JP
    localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS 2>/dev/null || true
    localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
    localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
    localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
    localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
    localedef -i se_NO -f UTF-8 se_NO.UTF-8
    localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
    localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
    localedef -i zh_CN -f GB18030 zh_CN.GB18030
    localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
    localedef -i zh_TW -f UTF-8 zh_TW.UTF-8

    # -- /etc/nsswitch.conf -----------------------------------------------------
    cat > /etc/nsswitch.conf << 'NSSWITCH'
# Begin /etc/nsswitch.conf
passwd: files
group: files
shadow: files
hosts: files dns
networks: files
protocols: files
services: files
ethers: files
rpc: files
# End /etc/nsswitch.conf
NSSWITCH

    # -- Timezone data (tzdata2024a, extracted in-place) ------------------------
    local tz_tarball
    tz_tarball="$(fetch "$TZDATA_URL")"
    mkdir -p /tmp/tzdata-build
    tar -xf "$tz_tarball" -C /tmp/tzdata-build
    cd /tmp/tzdata-build

    ZONEINFO=/usr/share/zoneinfo
    mkdir -pv "${ZONEINFO}/posix" "${ZONEINFO}/right"

    for tz in etcetera southamerica northamerica europe africa antarctica \
               asia australasia backward; do
        zic -L /dev/null   -d "${ZONEINFO}"       ${tz}
        zic -L /dev/null   -d "${ZONEINFO}/posix" ${tz}
        zic -L leapseconds -d "${ZONEINFO}/right"  ${tz}
    done

    cp -v zone.tab zone1970.tab iso3166.tab "${ZONEINFO}"
    zic -d "${ZONEINFO}" -p America/New_York
    unset ZONEINFO

    # Default timezone: UTC
    ln -sfv /usr/share/zoneinfo/UTC /etc/localtime

    cd /tmp && rm -rf /tmp/tzdata-build

    # -- /etc/ld.so.conf --------------------------------------------------------
    cat > /etc/ld.so.conf << 'LDSOCONF'
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

# Add an include directory
include /etc/ld.so.conf.d/*.conf
# End /etc/ld.so.conf
LDSOCONF
    mkdir -pv /etc/ld.so.conf.d

    rm -rf "$src"
}

build_zlib() {
    local src
    src="$(unpack "$ZLIB_URL")"
    cd "$src"
    ./configure --prefix=/usr
    make
    make check || true
    make install
    rm -fv /usr/lib/libz.a
    rm -rf "$src"
}

build_bzip2() {
    local src
    src="$(unpack "$BZIP2_URL")"
    cd "$src"

    # Apply the documentation install patch
    patch -Np1 -i "../bzip2-${BZIP2_VERSION}-install_docs-1.patch"

    # Fix symlink path — strip the $(PREFIX)/bin/ prefix so the symlink is relative
    # shellcheck disable=SC2016  # $(PREFIX) is a Makefile variable, not a shell expansion
    sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
    # Fix man page install path
    sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile

    # Build the shared library first, then the static tools
    make -f Makefile-libbz2_so
    make clean
    make
    make PREFIX=/usr install

    # Install the shared library and set up the symlink
    cp -av libbz2.so.* /usr/lib
    ln -sv libbz2.so.1.0.8 /usr/lib/libbz2.so

    # Replace the static bzip2 binary with the dynamically-linked one
    cp -v bzip2-shared /usr/bin/bzip2
    for i in /usr/bin/bzcat /usr/bin/bunzip2; do
        ln -sfv bzip2 "$i"
    done
    rm -fv /usr/lib/libbz2.a
    rm -rf "$src"
}

build_xz() {
    # In LFS 12.1 Ch.8, XZ is the same version (5.4.6) as the Ch.6 cross-build.
    # We build it natively here (no cross flags, no DESTDIR).
    local src
    src="$(unpack "$XZ_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-static \
                 --docdir="/usr/share/doc/xz-${XZ_VERSION}"
    make
    make check || true
    make install
    rm -rf "$src"
}

build_zstd() {
    local src
    src="$(unpack "$ZSTD_URL")"
    cd "$src"
    make prefix=/usr
    make check || true
    make prefix=/usr install
    rm -v /usr/lib/libzstd.a
    rm -rf "$src"
}

build_file() {
    # In LFS 12.1 Ch.8, File is the same version (5.45) as the Ch.6 cross-build.
    # Native build — plain configure, no cross flags.
    local src
    src="$(unpack "$FILE_URL")"
    cd "$src"
    ./configure --prefix=/usr
    make
    make check || true
    make install
    rm -rf "$src"
}

build_readline() {
    local src
    src="$(unpack "$READLINE_URL")"
    cd "$src"

    # Remove the backup-file installation step and the broken shlib path sed
    sed -i '/MV.*old/d' Makefile.in
    sed -i '/{OLDSUFF}/c:' support/shlib-install

    # Apply upstream fixes patch (LFS 12.1 uses -3)
    patch -Np1 -i "../readline-8.2-upstream_fixes-3.patch"

    ./configure --prefix=/usr \
                --disable-static \
                --with-curses \
                --docdir="/usr/share/doc/readline-${READLINE_VERSION}"
    make SHLIB_LIBS="-lncursesw"
    make SHLIB_LIBS="-lncursesw" install
    install -v -m644 doc/*.{ps,pdf,html,dvi} "/usr/share/doc/readline-${READLINE_VERSION}" 2>/dev/null || true
    rm -rf "$src"
}

build_m4() {
    # In LFS 12.1 Ch.8, M4 is the same version (1.4.19) as the Ch.6 cross-build.
    local src
    src="$(unpack "$M4_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    make check || true
    make install
    rm -rf "$src"
}

build_bc() {
    local src
    src="$(unpack "$BC_URL")"
    cd "$src"
    CC=gcc ./configure --prefix=/usr -G -O3 -r
    make
    make test || true
    make install
    rm -rf "$src"
}

build_flex() {
    local src
    src="$(unpack "$FLEX_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --docdir="/usr/share/doc/flex-${FLEX_VERSION}" \
                 --disable-static
    make
    make check || true
    make install
    ln -sv flex   /usr/bin/lex
    ln -sv flex.1 /usr/share/man/man1/lex.1
    rm -rf "$src"
}

build_tcl() {
    local src
    src="$(unpack "$TCL_URL")"
    cd "$src"

    # Set SRCDIR before entering unix/ — used by sed fixups below
    local SRCDIR
    SRCDIR="$(pwd)"
    cd unix
    ./configure --prefix=/usr \
                --mandir=/usr/share/man
    make

    # Fix embedded build-tree paths in the installed config scripts
    sed -e "s|${SRCDIR}/unix|/usr/lib|" \
        -e "s|${SRCDIR}|/usr/include|" \
        -i tclConfig.sh

    sed -e "s|${SRCDIR}/unix/pkgs/tdbc1.1.5|/usr/lib/tdbc1.1.5|" \
        -e "s|${SRCDIR}/pkgs/tdbc1.1.5/generic|/usr/include|" \
        -e "s|${SRCDIR}/pkgs/tdbc1.1.5/library|/usr/lib/tcl8.6|" \
        -e "s|${SRCDIR}/pkgs/tdbc1.1.5|/usr/include|" \
        -i pkgs/tdbc1.1.5/tdbcConfig.sh

    sed -e "s|${SRCDIR}/unix/pkgs/itcl4.2.3|/usr/lib/itcl4.2.3|" \
        -e "s|${SRCDIR}/pkgs/itcl4.2.3/generic|/usr/include|" \
        -e "s|${SRCDIR}/pkgs/itcl4.2.3|/usr/include|" \
        -i pkgs/itcl4.2.3/itclConfig.sh

    unset SRCDIR

    make test || true
    make install
    chmod -v u+w /usr/lib/libtcl8.6.so
    make install-private-headers
    ln -sfv tclsh8.6 /usr/bin/tclsh
    mv /usr/share/man/man3/{Thread,Tcl_Thread}.3
    rm -rf "$src"
}

build_expect() {
    local src
    src="$(unpack "$EXPECT_URL")"
    cd "$src"

    # No gcc15 patch in LFS 12.1 — that patch was added in 12.2+.
    ./configure --prefix=/usr \
                --with-tcl=/usr/lib \
                --enable-shared \
                --mandir=/usr/share/man \
                --with-tclinclude=/usr/include
    make
    make test || true
    make install
    ln -svf "expect${EXPECT_VERSION}/libexpect${EXPECT_VERSION}.so" /usr/lib
    rm -rf "$src"
}

build_dejagnu() {
    local src
    src="$(unpack "$DEJAGNU_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi || true
    makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi || true
    make check || true
    make install
    install -v -dm755 "/usr/share/doc/dejagnu-${DEJAGNU_VERSION}"
    install -v -m644 doc/dejagnu.{html,txt} "/usr/share/doc/dejagnu-${DEJAGNU_VERSION}" 2>/dev/null || true
    rm -rf "$src"
}

build_pkgconf() {
    local src
    src="$(unpack "$PKGCONF_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-static \
                 --docdir="/usr/share/doc/pkgconf-${PKGCONF_VERSION}"
    make
    make install
    ln -sv pkgconf   /usr/bin/pkg-config
    ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
    rm -rf "$src"
}

build_binutils() {
    # In LFS 12.1 Ch.8, Binutils is the same version (2.42) as the Ch.5 cross-build.
    # Native build — no cross flags.
    local src
    src="$(unpack "$BINUTILS_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --sysconfdir=/etc \
                 --enable-gold \
                 --enable-ld=default \
                 --enable-plugins \
                 --enable-shared \
                 --disable-werror \
                 --enable-64-bit-bfd \
                 --with-system-zlib \
                 --enable-default-hash-style=gnu
    make tooldir=/usr
    make -k check || true
    make tooldir=/usr install
    rm -fv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a
    rm -rf "$src"
}

build_gmp() {
    # In LFS 12.1 Ch.8, GMP is the same version (6.3.0) as the Ch.5 cross-build.
    local src
    src="$(unpack "$GMP_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --enable-cxx \
                 --disable-static \
                 --docdir="/usr/share/doc/gmp-${GMP_VERSION}"
    make
    make html
    make check 2>&1 | tee /tmp/gmp-check-log || true
    awk '/# PASS:/{total+=$3} ; END{print "GMP passed:", total}' /tmp/gmp-check-log || true
    rm -f /tmp/gmp-check-log
    make install
    make install-html
    rm -rf "$src"
}

build_mpfr() {
    # In LFS 12.1 Ch.8, MPFR is the same version (4.2.1) as the Ch.5 cross-build.
    local src
    src="$(unpack "$MPFR_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-static \
                 --enable-thread-safe \
                 --docdir="/usr/share/doc/mpfr-${MPFR_VERSION}"
    make
    make html
    make check || true
    make install
    make install-html
    rm -rf "$src"
}

build_mpc() {
    # In LFS 12.1 Ch.8, MPC is the same version (1.3.1) as the Ch.5 cross-build.
    local src
    src="$(unpack "$MPC_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-static \
                 --docdir="/usr/share/doc/mpc-${MPC_VERSION}"
    make
    make html
    make check || true
    make install
    make install-html
    rm -rf "$src"
}

build_attr() {
    local src
    src="$(unpack "$ATTR_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-static \
                 --sysconfdir=/etc \
                 --docdir="/usr/share/doc/attr-${ATTR_VERSION}"
    make
    make check || true
    make install
    rm -rf "$src"
}

build_acl() {
    local src
    src="$(unpack "$ACL_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-static \
                 --docdir="/usr/share/doc/acl-${ACL_VERSION}"
    make
    make install
    rm -rf "$src"
}

build_libcap() {
    local src
    src="$(unpack "$LIBCAP_URL")"
    cd "$src"
    # Prevent installation of the static library
    sed -i '/install -m.*STA/d' libcap/Makefile
    make prefix=/usr lib=lib
    make test || true
    make prefix=/usr lib=lib install
    rm -rf "$src"
}

build_libxcrypt() {
    local src
    src="$(unpack "$LIBXCRYPT_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --enable-hashes=strong,glibc \
                 --enable-obsolete-api=no \
                 --disable-static \
                 --disable-failure-tokens
    make
    make check || true
    make install
    rm -rf "$src"
}

build_shadow() {
    local src
    src="$(unpack "$SHADOW_URL")"
    cd "$src"

    # Remove the duplicate groups program and man pages managed elsewhere
    # shellcheck disable=SC2016  # $(EXEEXT) is a Makefile variable, not a shell expansion
    sed -i 's/groups$(EXEEXT) //' src/Makefile.in
    find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} \;
    find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
    find man -name Makefile.in -exec sed -i 's/passwd\.5 / /' {} \;

    # Switch to yescrypt password hashing and fix mail/path settings
    sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
        -e 's:/var/spool/mail:/var/mail:' \
        -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' \
        -i etc/login.defs

    # Ensure /usr/bin/passwd exists for configure check
    touch /usr/bin/passwd

    ./configure --sysconfdir=/etc \
                --disable-static \
                --with-{b,yes}crypt \
                --without-libbsd \
                --with-group-name-max-length=32
    make
    make exec_prefix=/usr install
    make -C man install-man

    # Enable shadow passwords and shadow groups
    pwconv
    grpconv

    # Set a blank root password so the system boots without prompting
    # NOTE: useradd -D --gid 999 is the LFS book step; passwd root prompts
    # interactively in 12.1, so we use passwd -d root to clear it non-interactively.
    mkdir -p /etc/default
    useradd -D --gid 999 || true
    passwd -d root

    rm -rf "$src"
}

build_gcc() {
    # In LFS 12.1 Ch.8, GCC is the same version (13.2.0) as the Ch.5/6 cross-build.
    # Native build — no cross flags.
    local src
    src="$(unpack "$GCC_URL")"
    cd "$src"

    # Adjust the default 64-bit multilib directory name
    case "$(uname -m)" in
        x86_64)
            sed -e '/m64=/s/lib64/lib/' \
                -i.orig gcc/config/i386/t-linux64
            ;;
    esac

    with_clean_build "$src"
    ../configure --prefix=/usr \
                 LD=ld \
                 --enable-languages=c,c++ \
                 --enable-default-pie \
                 --enable-default-ssp \
                 --disable-multilib \
                 --disable-bootstrap \
                 --disable-fixincludes \
                 --with-system-zlib
    make

    # Test suite — run as tester (must exist); non-fatal
    ulimit -s 32768 || true
    chown -R tester . 2>/dev/null || true
    su tester -c "PATH=$PATH make -k check" || true

    make install

    # Fix ownership of the include/ tree
    chown -v -R root:root \
        "/usr/lib/gcc/$(gcc -dumpmachine)/${GCC_VERSION}/include" \
        "/usr/lib/gcc/$(gcc -dumpmachine)/${GCC_VERSION}/include-fixed" \
        2>/dev/null || true

    # Compatibility symlinks
    ln -svr /usr/bin/cpp /usr/lib
    ln -sv gcc.1 /usr/share/man/man1/cc.1

    # Link the LTO plugin for binutils bfd
    mkdir -pv /usr/lib/bfd-plugins
    ln -sfv "../../libexec/gcc/$(gcc -dumpmachine)/${GCC_VERSION}/liblto_plugin.so" \
            /usr/lib/bfd-plugins/

    # Sanity check — verify the toolchain is self-consistent
    echo 'int main(){}' > dummy.c
    cc dummy.c -v -Wl,--verbose > /tmp/gcc-dummy.log 2>&1
    readelf -l a.out | grep ': /lib' || true
    grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' /tmp/gcc-dummy.log || true
    grep -B4 '^ /usr/include' /tmp/gcc-dummy.log || true
    grep 'SEARCH.*/usr/lib' /tmp/gcc-dummy.log | sed 's|; |\n|g' || true
    grep "/lib.*/libc.so.6 " /tmp/gcc-dummy.log || true
    grep found /tmp/gcc-dummy.log || true
    rm -v dummy.c a.out /tmp/gcc-dummy.log 2>/dev/null || true

    # Move gdb helper scripts to the proper location
    mkdir -pv /usr/share/gdb/auto-load/usr/lib
    mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib 2>/dev/null || true

    rm -rf "$src"
}
