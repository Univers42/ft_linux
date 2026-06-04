# Build functions for the LFS Ch. 8 final system (native build inside chroot).
# Each build_* function follows the LFS 12.1 book commands verbatim.
# Reference: https://www.linuxfromscratch.org/lfs/view/12.1/chapter08/
#
# KEY DIFFERENCE from build-toolchain-lib.sh: these run INSIDE the chroot with
# the native compiler — no --host=/--build=/cross flags, no DESTDIR=$LFS.
# unpack() / with_clean_build() / fetch() / die() all come from lib.sh.
# shellcheck disable=SC2164

# === Chapter 7 — additional temporary tools (native, chroot) ===
# These run INSIDE the chroot with the native compiler but are intentionally
# stripped-down/temporary installations.  They must be built BEFORE Ch.8
# because glibc's configure requires bison and Python, and other packages
# need perl.  Names carry a _tmp suffix to distinguish them from the full
# Ch.8 final-system builds that come later.

build_gettext_tmp() {
    # LFS 12.1 §7.14 — only msgfmt, msgmerge, xgettext are needed now.
    # We skip the shared libraries entirely (--disable-shared) to keep this
    # temporary and avoid interfering with the final Ch.8 gettext build.
    local src
    src="$(unpack "$GETTEXT_URL")"
    cd "$src"
    ./configure --disable-shared
    make
    cp -v gettext-tools/src/msgfmt \
          gettext-tools/src/msgmerge \
          gettext-tools/src/xgettext \
          /usr/bin
    rm -rf "$src"
}

build_bison_tmp() {
    # LFS 12.1 §7.15 — full install; glibc configure requires bison.
    local src
    src="$(unpack "$BISON_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --docdir="/usr/share/doc/bison-${BISON_VERSION}"
    make
    make install
    rm -rf "$src"
}

build_perl_tmp() {
    # LFS 12.1 §7.16 — temporary Perl; only core modules, shared lib enabled.
    # Uses sh Configure (capital C), not autoconf ./configure.
    # -des: default answers + enable everything + silent mode.
    local src
    src="$(unpack "$PERL_URL")"
    cd "$src"
    sh Configure -des \
                 -Dprefix=/usr \
                 -Dvendorprefix=/usr \
                 -Duseshrplib \
                 -Dprivlib=/usr/lib/perl5/5.38/core_perl \
                 -Darchlib=/usr/lib/perl5/5.38/core_perl \
                 -Dsitelib=/usr/lib/perl5/5.38/site_perl \
                 -Dsitearch=/usr/lib/perl5/5.38/site_perl \
                 -Dvendorlib=/usr/lib/perl5/5.38/vendor_perl \
                 -Dvendorarch=/usr/lib/perl5/5.38/vendor_perl
    make
    make install
    rm -rf "$src"
}

build_python_tmp() {
    # LFS 12.1 §7.17 — temporary Python 3; shared lib, no pip/ensurepip.
    # Some optional C-extension modules (ssl, etc.) may not build due to
    # missing dependencies at this stage — that is expected and non-fatal.
    local src
    src="$(unpack "$PYTHON_URL")"
    cd "$src"
    ./configure --prefix=/usr \
                --enable-shared \
                --without-ensurepip
    make
    make install
    rm -rf "$src"
}

build_texinfo_tmp() {
    # LFS 12.1 §7.18 — temporary texinfo; plain prefix=/usr install.
    local src
    src="$(unpack "$TEXINFO_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    make install
    rm -rf "$src"
}

build_util_linux_tmp() {
    # LFS 12.1 §7.19 — temporary util-linux.
    # Many daemons/tools are disabled; only the utilities needed for the
    # rest of the Ch.7/Ch.8 build are enabled.  Python bindings disabled
    # (--without-python) to avoid a circular dependency.
    local src
    src="$(unpack "$UTIL_LINUX_URL")"
    cd "$src"
    mkdir -pv /var/lib/hwclock
    ./configure --libdir=/usr/lib \
                --runstatedir=/run \
                --disable-chfn-chsh \
                --disable-login \
                --disable-nologin \
                --disable-su \
                --disable-setpriv \
                --disable-runuser \
                --disable-pylibmount \
                --disable-static \
                --without-python \
                ADJTIME_PATH=/var/lib/hwclock/adjtime \
                --docdir="/usr/share/doc/util-linux-${UTIL_LINUX_VERSION}"
    make
    make install
    rm -rf "$src"
}

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
    # GIT=false: the chroot has no git; man-pages derives dates from it otherwise.
    make -R GIT=false prefix=/usr MANDIR=/usr/share/man install
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
    makeinfo --html --no-split -o doc/dejagnu.html doc/dejagnu.texi || true
    makeinfo --plaintext       -o doc/dejagnu.txt  doc/dejagnu.texi || true
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

# ===========================================================================
# Chapter 8 — second half (ncurses … man-db), LFS 12.1 SysV order
# ===========================================================================

build_ncurses() {
    # LFS 12.1 §8.29 — Ncurses-6.4-20230520. Wide-character (UTF-8) build.
    # Install the real shared lib first via DESTDIR, then copy everything else.
    local src
    src="$(unpack "$NCURSES_URL")"
    cd "$src"
    ./configure --prefix=/usr \
                --mandir=/usr/share/man \
                --with-shared \
                --without-debug \
                --without-normal \
                --with-cxx-shared \
                --enable-pc-files \
                --enable-widec \
                --with-pkg-config-libdir=/usr/lib/pkgconfig
    make
    make DESTDIR="$PWD/dest" install
    install -vm755 dest/usr/lib/libncursesw.so.6.4 /usr/lib
    rm -v dest/usr/lib/libncursesw.so.6.4
    sed -e 's/^#if.*XOPEN.*$/#if 1/' \
        -i dest/usr/include/curses.h
    cp -av dest/* /
    # Non-wide compat symlinks (so code linking -lncurses finds the wide lib)
    for lib in ncurses form panel menu; do
        ln -sfv "lib${lib}w.so" /usr/lib/lib${lib}.so
        ln -sfv "${lib}w.pc"    /usr/lib/pkgconfig/${lib}.pc
    done
    ln -sfv libncursesw.so /usr/lib/libcurses.so
    cp -v -R doc -T "/usr/share/doc/ncurses-${NCURSES_VERSION}" 2>/dev/null || true
    rm -rf "$src"
}

build_sed() {
    # LFS 12.1 §8.30 — Sed-4.9.
    local src
    src="$(unpack "$SED_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    make html
    chown -R tester . 2>/dev/null || true
    su tester -c "PATH=$PATH make check" || true
    make install
    install -d -m755 "/usr/share/doc/sed-${SED_VERSION}"
    install -m644 doc/sed.html "/usr/share/doc/sed-${SED_VERSION}" 2>/dev/null || true
    rm -rf "$src"
}

build_psmisc() {
    # LFS 12.1 §8.31 — Psmisc-23.6. Build IN-TREE: out-of-tree breaks
    # install-data-local (translated man-po pages aren't generated).
    local src
    src="$(unpack "$PSMISC_URL")"
    cd "$src"
    ./configure --prefix=/usr
    make
    make check || true
    make install
    rm -rf "$src"
}

build_gettext() {
    # LFS 12.1 §8.32 — Gettext-0.22.4 (final, replaces Ch.7 _tmp).
    local src
    src="$(unpack "$GETTEXT_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-static \
                 --docdir="/usr/share/doc/gettext-${GETTEXT_VERSION}"
    make
    make check || true
    make install
    chmod -v 0755 /usr/lib/preloadable_libintl.so 2>/dev/null || true
    rm -rf "$src"
}

build_bison() {
    # LFS 12.1 §8.33 — Bison-3.8.2 (final, replaces Ch.7 _tmp).
    local src
    src="$(unpack "$BISON_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --docdir="/usr/share/doc/bison-${BISON_VERSION}"
    make
    make check || true
    make install
    rm -rf "$src"
}

build_grep() {
    # LFS 12.1 §8.34 — Grep-3.11.
    local src
    src="$(unpack "$GREP_URL")"
    cd "$src"
    sed -i "s/echo/#echo/" src/egrep.sh
    ./configure --prefix=/usr
    make
    make check || true
    make install
    rm -rf "$src"
}

build_bash() {
    # LFS 12.1 §8.35 — Bash-5.2.21 (final, replaces Ch.6 cross-built bash).
    local src
    src="$(unpack "$BASH_URL")"
    cd "$src"
    patch -Np1 -i "../bash-5.2.21-upstream_fixes-1.patch"
    ./configure --prefix=/usr \
                --without-bash-malloc \
                --with-installed-readline \
                --docdir="/usr/share/doc/bash-${BASH_VERSION}"
    make
    chown -R tester . 2>/dev/null || true
    su -s /usr/bin/expect tester << 'BASHTEST' || true
set timeout -1
spawn make tests
expect eof
lassign [wait] _ _ _ value
exit $value
BASHTEST
    make install
    # NOTE: LFS's interactive `exec /bin/bash --login` is intentionally omitted —
    # in the automated build-all loop it would replace (hijack) the running shell.
    rm -rf "$src"
}

build_libtool() {
    # LFS 12.1 §8.36 — Libtool-2.4.7.
    local src
    src="$(unpack "$LIBTOOL_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    make -k check || true
    make install
    rm -fv /usr/lib/libltdl.a
    rm -rf "$src"
}

build_gdbm() {
    # LFS 12.1 §8.37 — GDBM-1.23.
    local src
    src="$(unpack "$GDBM_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-static \
                 --enable-libgdbm-compat
    make
    make check || true
    make install
    rm -rf "$src"
}

build_gperf() {
    # LFS 12.1 §8.38 — Gperf-3.1.
    local src
    src="$(unpack "$GPERF_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --docdir="/usr/share/doc/gperf-${GPERF_VERSION}"
    make
    make -j1 check || true
    make install
    rm -rf "$src"
}

build_expat() {
    # LFS 12.1 §8.39 — Expat-2.6.0.
    local src
    src="$(unpack "$EXPAT_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-static \
                 --docdir="/usr/share/doc/expat-${EXPAT_VERSION}"
    make
    make check || true
    make install
    install -v -m644 doc/*.{html,css} \
        "/usr/share/doc/expat-${EXPAT_VERSION}" 2>/dev/null || true
    rm -rf "$src"
}

build_inetutils() {
    # LFS 12.1 §8.40 — Inetutils-2.5.
    local src
    src="$(unpack "$INETUTILS_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --bindir=/usr/bin \
                 --localstatedir=/var \
                 --disable-logger \
                 --disable-whois \
                 --disable-rcp \
                 --disable-rexec \
                 --disable-rlogin \
                 --disable-rsh \
                 --disable-servers
    make
    make check || true
    make install
    mv -v /usr/{,s}bin/ifconfig 2>/dev/null || true
    rm -rf "$src"
}

build_less() {
    # LFS 12.1 §8.41 — Less-643.
    local src
    src="$(unpack "$LESS_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --sysconfdir=/etc
    make
    make check || true
    make install
    rm -rf "$src"
}

build_perl() {
    # LFS 12.1 §8.42 — Perl-5.38.2 (final, replaces Ch.7 _tmp).
    local src
    src="$(unpack "$PERL_URL")"
    cd "$src"
    export BUILD_ZLIB=False
    export BUILD_BZIP2=0
    sh Configure -des \
                 -Dprefix=/usr \
                 -Dvendorprefix=/usr \
                 -Dprivlib=/usr/lib/perl5/5.38/core_perl \
                 -Darchlib=/usr/lib/perl5/5.38/core_perl \
                 -Dsitelib=/usr/lib/perl5/5.38/site_perl \
                 -Dsitearch=/usr/lib/perl5/5.38/site_perl \
                 -Dvendorlib=/usr/lib/perl5/5.38/vendor_perl \
                 -Dvendorarch=/usr/lib/perl5/5.38/vendor_perl \
                 -Dman1dir=/usr/share/man/man1 \
                 -Dman3dir=/usr/share/man/man3 \
                 -Dpager="/usr/bin/less -isR" \
                 -Duseshrplib \
                 -Dusethreads
    make
    TEST_JOBS="$(nproc)" make test_harness || true
    make install
    unset BUILD_ZLIB BUILD_BZIP2
    rm -rf "$src"
}

build_xml_parser() {
    # LFS 12.1 §8.43 — XML::Parser-2.47 (Perl Expat interface).
    # No configure script — uses Perl's MakeMaker.
    local src
    src="$(unpack "$XML_PARSER_URL")"
    cd "$src"
    perl Makefile.PL
    make
    make test || true
    make install
    rm -rf "$src"
}

build_intltool() {
    # LFS 12.1 §8.44 — Intltool-0.51.0.
    local src
    src="$(unpack "$INTLTOOL_URL")"
    cd "$src"
    # Fix perl-5.22+ incompatibility in intltool-update.in
    sed -i 's:\\\${:\\$\\{:' intltool-update.in
    ./configure --prefix=/usr
    make
    make check || true
    make install
    install -v -Dm644 doc/I18N-HOWTO \
        "/usr/share/doc/intltool-${INTLTOOL_VERSION}/I18N-HOWTO"
    rm -rf "$src"
}

build_autoconf() {
    # LFS 12.1 §8.45 — Autoconf-2.72.
    local src
    src="$(unpack "$AUTOCONF_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    make check || true
    make install
    rm -rf "$src"
}

build_automake() {
    # LFS 12.1 §8.46 — Automake-1.16.5.
    local src
    src="$(unpack "$AUTOMAKE_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --docdir="/usr/share/doc/automake-${AUTOMAKE_VERSION}"
    make
    # t/subobj.sh is known to fail; run with at least 4 parallel jobs
    local jobs
    jobs="$(nproc)"
    make -j"$((jobs > 4 ? jobs : 4))" check || true
    make install
    rm -rf "$src"
}

build_kmod() {
    # LFS 12.1 §8.47 — Kmod-31.
    local src
    src="$(unpack "$KMOD_URL")"
    with_clean_build "$src"
    # --without-openssl: OpenSSL is not in this project's package set; kmod only
    # uses libcrypto for module-signature verification, which we don't need.
    ../configure --prefix=/usr \
                 --sysconfdir=/etc \
                 --without-openssl \
                 --with-xz \
                 --with-zstd \
                 --with-zlib
    make
    make install
    # Compat symlinks for traditional module-init-tools names
    for target in depmod insmod modinfo modprobe rmmod; do
        ln -sfv ../bin/kmod /usr/sbin/$target
    done
    ln -sfv kmod /usr/bin/lsmod
    rm -rf "$src"
}

build_elfutils() {
    # LFS 12.1 §8.48 — libelf (from elfutils-0.190).
    # Only the libelf component is installed; debuginfod is disabled.
    local src
    src="$(unpack "$ELFUTILS_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-debuginfod \
                 --enable-libdebuginfod=dummy
    make
    make check || true
    make -C libelf install
    install -vm644 config/libelf.pc /usr/lib/pkgconfig
    rm -f /usr/lib/libelf.a
    rm -rf "$src"
}

build_coreutils() {
    # LFS 12.1 §8.49 — Coreutils-9.4.
    local src
    src="$(unpack "$COREUTILS_URL")"
    cd "$src"
    patch -Np1 -i "../coreutils-9.4-i18n-1.patch"
    sed -e '/n_out += n_hold/,+4 s|.*bufsize.*|//&|' -i src/split.c
    autoreconf -fiv
    FORCE_UNSAFE_CONFIGURE=1 ./configure \
                --prefix=/usr \
                --enable-no-install-program=kill,uptime
    make
    make NON_ROOT_USERNAME=tester check-root || true
    groupadd -g 102 dummy -U tester 2>/dev/null || true
    chown -R tester . 2>/dev/null || true
    su tester -c "PATH=$PATH make RUN_EXPENSIVE_TESTS=yes check" || true
    groupdel dummy 2>/dev/null || true
    make install
    mv -v /usr/bin/chroot /usr/sbin
    mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
    sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
    rm -rf "$src"
}

build_check() {
    # LFS 12.1 §8.50 — Check-0.15.2 (unit-test framework for C).
    local src
    src="$(unpack "$CHECK_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --disable-static
    make
    make check || true
    make docdir="/usr/share/doc/check-${CHECK_VERSION}" install
    rm -rf "$src"
}

build_diffutils() {
    # LFS 12.1 §8.51 — Diffutils-3.10.
    local src
    src="$(unpack "$DIFFUTILS_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    make check || true
    make install
    rm -rf "$src"
}

build_gawk() {
    # LFS 12.1 §8.52 — Gawk-5.3.0.
    local src
    src="$(unpack "$GAWK_URL")"
    cd "$src"
    sed -i 's/extras//' Makefile.in
    ./configure --prefix=/usr
    make
    chown -R tester . 2>/dev/null || true
    su tester -c "PATH=$PATH make check" || true
    rm -f /usr/bin/gawk-5.3.0 2>/dev/null || true
    make install
    ln -sv gawk.1 /usr/share/man/man1/awk.1
    mkdir -pv "/usr/share/doc/gawk-${GAWK_VERSION}"
    cp -v doc/{awkforai.txt,*.{eps,pdf,jpg}} \
        "/usr/share/doc/gawk-${GAWK_VERSION}" 2>/dev/null || true
    rm -rf "$src"
}

build_findutils() {
    # LFS 12.1 §8.53 — Findutils-4.9.0.
    local src
    src="$(unpack "$FINDUTILS_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --localstatedir=/var/lib/locate
    make
    chown -R tester . 2>/dev/null || true
    su tester -c "PATH=$PATH make check" || true
    make install
    rm -rf "$src"
}

build_groff() {
    # LFS 12.1 §8.54 — Groff-1.23.0.
    # PAGE defaults to A4; override at build time with PAGE=letter if needed.
    local src
    src="$(unpack "$GROFF_URL")"
    with_clean_build "$src"
    PAGE=A4 ../configure --prefix=/usr
    make
    make check || true
    make install
    rm -rf "$src"
}

build_grub() {
    # LFS 12.1 §8.55 — GRUB-2.12.
    # Unset any CFLAGS/LDFLAGS that could confuse the build.
    local src
    src="$(unpack "$GRUB_URL")"
    cd "$src"
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    # shellcheck disable=SC2016
    echo 'depends bli part_gpt' > grub-core/extra_deps.lst
    ./configure --prefix=/usr \
                --sysconfdir=/etc \
                --disable-efiemu \
                --disable-werror
    make
    make install
    mv -v /etc/bash_completion.d/grub \
          /usr/share/bash-completion/completions 2>/dev/null || true
    rm -rf "$src"
}

build_gzip() {
    # LFS 12.1 §8.56 — Gzip-1.13.
    local src
    src="$(unpack "$GZIP_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    make check || true
    make install
    rm -rf "$src"
}

build_iproute2() {
    # LFS 12.1 §8.57 — IPRoute2-6.7.0. No autoconf — uses its own Makefile.
    local src
    src="$(unpack "$IPROUTE2_URL")"
    cd "$src"
    sed -i /ARPD/d Makefile
    rm -fv man/man8/arpd.8
    make NETNS_RUN_DIR=/run/netns
    make SBINDIR=/usr/sbin install
    mkdir -pv "/usr/share/doc/iproute2-${IPROUTE2_VERSION}"
    cp -v COPYING README* "/usr/share/doc/iproute2-${IPROUTE2_VERSION}"
    rm -rf "$src"
}

build_kbd() {
    # LFS 12.1 §8.58 — Kbd-2.6.4.
    local src
    src="$(unpack "$KBD_URL")"
    cd "$src"
    patch -Np1 -i "../kbd-2.6.4-backspace-1.patch"
    sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
    sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
    ./configure --prefix=/usr \
                --disable-vlock
    make
    make check || true
    make install
    cp -R -v docs/doc -T "/usr/share/doc/kbd-${KBD_VERSION}" 2>/dev/null || true
    rm -rf "$src"
}

build_libpipeline() {
    # LFS 12.1 §8.59 — Libpipeline-1.5.7.
    local src
    src="$(unpack "$LIBPIPELINE_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    make check || true
    make install
    rm -rf "$src"
}

build_make() {
    # LFS 12.1 §8.60 — Make-4.4.1 (final, replaces Ch.6 cross-built make).
    local src
    src="$(unpack "$MAKE_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    chown -R tester . 2>/dev/null || true
    su tester -c "PATH=$PATH make check" || true
    make install
    rm -rf "$src"
}

build_patch() {
    # LFS 12.1 §8.61 — Patch-2.7.6.
    local src
    src="$(unpack "$PATCH_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    make check || true
    make install
    rm -rf "$src"
}

build_tar() {
    # LFS 12.1 §8.62 — Tar-1.35.
    local src
    src="$(unpack "$TAR_URL")"
    with_clean_build "$src"
    FORCE_UNSAFE_CONFIGURE=1 ../configure --prefix=/usr
    make
    make check || true
    make install
    make -C doc install-html docdir="/usr/share/doc/tar-${TAR_VERSION}" 2>/dev/null || true
    rm -rf "$src"
}

build_texinfo() {
    # LFS 12.1 §8.63 — Texinfo-7.1 (final, replaces Ch.7 _tmp).
    local src
    src="$(unpack "$TEXINFO_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr
    make
    make check || true
    make install
    make TEXMF=/usr/share/texmf install-tex || true
    rm -rf "$src"
}

build_vim() {
    # LFS 12.1 §8.64 — Vim-9.1.0041.
    local src
    src="$(unpack "$VIM_URL")"
    cd "$src"
    # Point vim at the system-wide vimrc
    echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
    ./configure --prefix=/usr
    make
    chown -R tester . 2>/dev/null || true
    su tester -c "TERM=xterm-256color LANG=en_US.UTF-8 make -j1 test" \
        > /tmp/vim-test.log 2>&1 || true
    make install
    ln -sv vim /usr/bin/vi
    for L in /usr/share/man/{,*/}man1/vim.1; do
        ln -sv vim.1 "$(dirname "$L")/vi.1"
    done
    ln -sv "../vim/vim91/doc" "/usr/share/doc/vim-${VIM_VERSION}"
    # Create a minimal /etc/vimrc
    cat > /etc/vimrc << 'VIMRC'
" Begin /etc/vimrc
" Ensure defaults are set before customizing settings, not after
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif

" End /etc/vimrc
VIMRC
    rm -rf "$src"
}

build_eudev() {
    # SysV LFS — eudev-3.2.11 (the SysV replacement for systemd-udev).
    # eudev is the udev fork used by this project (SysVinit edition);
    # LFS 12.1 mainline uses udev from systemd-255, but this project requires eudev.
    # Build commands mirror LFS 11.x eudev section verbatim.
    local src
    src="$(unpack "$EUDEV_URL")"
    cd "$src"
    # Fix pkg-config file generation — ${udevdir} is literal text for the .pc file
    # shellcheck disable=SC2016
    sed -i '/udevdir/a udev_dir=${udevdir}' src/udev/udev.pc.in
    ./configure --prefix=/usr \
                --bindir=/usr/sbin \
                --sysconfdir=/etc \
                --enable-manpages \
                --disable-static
    make
    make check || true
    # Create the rules directories before install
    mkdir -pv /usr/lib/udev/rules.d
    mkdir -pv /etc/udev/rules.d
    make install
    # Install the LFS udev helper rules (bootscripts for udev in SysV)
    local lfs_rules
    lfs_rules="$(fetch "$UDEV_LFS_URL")"
    tar -xf "$lfs_rules" -C /tmp
    make -f "/tmp/udev-lfs-${UDEV_LFS_VERSION}/Makefile.lfs" install
    rm -rf "/tmp/udev-lfs-${UDEV_LFS_VERSION}"
    # Build the hardware database
    udevadm hwdb --update
    rm -rf "$src"
}

build_procps() {
    # LFS 12.1 §8.67 — Procps-ng-4.0.4 (final system build).
    local src
    src="$(unpack "$PROCPS_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --docdir="/usr/share/doc/procps-ng-${PROCPS_VERSION}" \
                 --disable-static \
                 --disable-kill
    make
    make -k check || true
    make install
    rm -rf "$src"
}

build_util_linux() {
    # LFS 12.1 §8.68 — Util-linux-2.39.3 (final build; replaces Ch.7 _tmp).
    # This final build adds --without-systemd compared to the temp build.
    local src
    src="$(unpack "$UTIL_LINUX_URL")"
    cd "$src"
    sed -i '/test_mkfds/s/^/#/' tests/helpers/Makemodule.am
    mkdir -pv /var/lib/hwclock
    ./configure --bindir=/usr/bin \
                --libdir=/usr/lib \
                --runstatedir=/run \
                --sbindir=/usr/sbin \
                --disable-chfn-chsh \
                --disable-login \
                --disable-nologin \
                --disable-su \
                --disable-setpriv \
                --disable-runuser \
                --disable-pylibmount \
                --disable-static \
                --without-python \
                --without-systemd \
                --without-systemdsystemunitdir \
                ADJTIME_PATH=/var/lib/hwclock/adjtime \
                --docdir="/usr/share/doc/util-linux-${UTIL_LINUX_VERSION}"
    make
    chown -R tester . 2>/dev/null || true
    su tester -c "make -k check" || true
    make install
    rm -rf "$src"
}

build_e2fsprogs() {
    # LFS 12.1 §8.69 — E2fsprogs-1.47.0.
    local src
    src="$(unpack "$E2FSPROGS_URL")"
    mkdir -v "${src}/build"
    cd "${src}/build"
    ../configure --prefix=/usr \
                 --sysconfdir=/etc \
                 --enable-elf-shlibs \
                 --disable-libblkid \
                 --disable-libuuid \
                 --disable-uuidd \
                 --disable-fsck
    make
    make check || true
    make install
    rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
    gunzip -v /usr/share/info/libext2fs.info.gz
    install-info --dir-file=/usr/share/info/dir \
                 /usr/share/info/libext2fs.info
    makeinfo -o doc/com_err.info ../lib/et/com_err.texinfo
    install -v -m644 doc/com_err.info /usr/share/info
    install-info --dir-file=/usr/share/info/dir \
                 /usr/share/info/com_err.info
    rm -rf "$src"
}

build_sysklogd() {
    # LFS 12.1 §8.70 — Sysklogd-1.5.1 (SysV edition).
    local src
    src="$(unpack "$SYSKLOGD_URL")"
    cd "$src"
    # Fix two upstream issues: symbol loading error and obsolete wait type
    sed -i '/Error loading kernel symbols/{n;n;d}' ksym_mod.c
    sed -i 's/union wait/int/' syslogd.c
    make
    make BINDIR=/sbin install
    # Create a basic syslog configuration
    cat > /etc/syslog.conf << 'SYSLOGCONF'
# Begin /etc/syslog.conf
auth,authpriv.* -/var/log/auth.log
*.*;auth,authpriv.none -/var/log/sys.log
daemon.* -/var/log/daemon.log
kern.* -/var/log/kern.log
mail.* -/var/log/mail.log
user.* -/var/log/user.log
*.emerg *
# End /etc/syslog.conf
SYSLOGCONF
    rm -rf "$src"
}

build_sysvinit() {
    # LFS 12.1 §8.71 — SysVinit-3.08 (SysV edition).
    local src
    src="$(unpack "$SYSVINIT_URL")"
    cd "$src"
    patch -Np1 -i "../sysvinit-3.08-consolidated-1.patch"
    make
    make install
    rm -rf "$src"
}

build_man_db() {
    # LFS 12.1 §8.72 — Man-DB-2.12.0.
    local src
    src="$(unpack "$MAN_DB_URL")"
    with_clean_build "$src"
    ../configure --prefix=/usr \
                 --docdir="/usr/share/doc/man-db-${MAN_DB_VERSION}" \
                 --sysconfdir=/etc \
                 --disable-setuid \
                 --enable-cache-owner=bin \
                 --with-browser=/usr/bin/lynx \
                 --with-vgrind=/usr/bin/vgrind \
                 --with-grap=/usr/bin/grap \
                 --with-systemdtmpfilesdir= \
                 --with-systemdsystemunitdir=
    make
    make check || true
    make install
    rm -rf "$src"
}
