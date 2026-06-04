# LFS 12.x package versions and download URLs.
# Pinned versions — change here, not in build scripts.
# Source of truth: https://www.linuxfromscratch.org/lfs/view/stable/
#
# Pure constants, sourced by the build scripts — "unused" here by design.
# shellcheck disable=SC2034

# -- Toolchain (Ch. 5-6) ----------------------------------------------------
BINUTILS_VERSION=2.42
BINUTILS_URL="https://sourceware.org/pub/binutils/releases/binutils-${BINUTILS_VERSION}.tar.xz"

GCC_VERSION=13.2.0
GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz"

# GCC needs MPFR, GMP, MPC source trees inside its own source dir.
MPFR_VERSION=4.2.1
MPFR_URL="https://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.xz"

GMP_VERSION=6.3.0
GMP_URL="https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz"

MPC_VERSION=1.3.1
MPC_URL="https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz"

# Kernel headers come from our chosen kernel source (set in lib.sh).
GLIBC_VERSION=2.39
GLIBC_URL="https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VERSION}.tar.xz"

# -- Ch. 6 temporary tools --------------------------------------------------
M4_VERSION=1.4.19
M4_URL="https://ftp.gnu.org/gnu/m4/m4-${M4_VERSION}.tar.xz"

NCURSES_VERSION=6.4
NCURSES_URL="https://invisible-mirror.net/archives/ncurses/ncurses-${NCURSES_VERSION}.tar.gz"

BASH_VERSION=5.2.21
BASH_URL="https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz"

COREUTILS_VERSION=9.4
COREUTILS_URL="https://ftp.gnu.org/gnu/coreutils/coreutils-${COREUTILS_VERSION}.tar.xz"

DIFFUTILS_VERSION=3.10
DIFFUTILS_URL="https://ftp.gnu.org/gnu/diffutils/diffutils-${DIFFUTILS_VERSION}.tar.xz"

FILE_VERSION=5.45
FILE_URL="https://astron.com/pub/file/file-${FILE_VERSION}.tar.gz"

FINDUTILS_VERSION=4.9.0
FINDUTILS_URL="https://ftp.gnu.org/gnu/findutils/findutils-${FINDUTILS_VERSION}.tar.xz"

GAWK_VERSION=5.3.0
GAWK_URL="https://ftp.gnu.org/gnu/gawk/gawk-${GAWK_VERSION}.tar.xz"

GREP_VERSION=3.11
GREP_URL="https://ftp.gnu.org/gnu/grep/grep-${GREP_VERSION}.tar.xz"

GZIP_VERSION=1.13
GZIP_URL="https://ftp.gnu.org/gnu/gzip/gzip-${GZIP_VERSION}.tar.xz"

MAKE_VERSION=4.4.1
MAKE_URL="https://ftp.gnu.org/gnu/make/make-${MAKE_VERSION}.tar.gz"

PATCH_VERSION=2.7.6
PATCH_URL="https://ftp.gnu.org/gnu/patch/patch-${PATCH_VERSION}.tar.xz"

SED_VERSION=4.9
SED_URL="https://ftp.gnu.org/gnu/sed/sed-${SED_VERSION}.tar.xz"

TAR_VERSION=1.35
TAR_URL="https://ftp.gnu.org/gnu/tar/tar-${TAR_VERSION}.tar.xz"

XZ_VERSION=5.4.6
XZ_URL="https://tukaani.org/xz/xz-${XZ_VERSION}.tar.xz"

# -- Ch. 7 (temporary tools) ------------------------------------------------
# Native builds run INSIDE the chroot, before Ch.8.
# These provide bison/python/perl that glibc's configure requires.
# Versions and MD5s from LFS 12.1 Chapter 3 package list.

GETTEXT_VERSION=0.22.4
GETTEXT_URL="https://ftp.gnu.org/gnu/gettext/gettext-${GETTEXT_VERSION}.tar.xz"
GETTEXT_MD5=2d8507d003ef3ddd1c172707ffa97ed8

BISON_VERSION=3.8.2
BISON_URL="https://ftp.gnu.org/gnu/bison/bison-${BISON_VERSION}.tar.xz"
BISON_MD5=c28f119f405a2304ff0a7ccdcc629713

PERL_VERSION=5.38.2
PERL_URL="https://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.xz"
PERL_MD5=d3957d75042918a23ec0abac4a2b7e0a

PYTHON_VERSION=3.12.2
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz"
PYTHON_MD5=e7c178b97bf8f7ccd677b94d614f7b3c

TEXINFO_VERSION=7.1
TEXINFO_URL="https://ftp.gnu.org/gnu/texinfo/texinfo-${TEXINFO_VERSION}.tar.xz"
TEXINFO_MD5=edd9928b4a3f82674bcc3551616eef3b

UTIL_LINUX_VERSION=2.39.3
UTIL_LINUX_URL="https://www.kernel.org/pub/linux/utils/util-linux/v2.39/util-linux-${UTIL_LINUX_VERSION}.tar.xz"
UTIL_LINUX_MD5=f3591e6970c017bb4bcd24ae762a98f5

# -- Ch. 8 (final system) ---------------------------------------------------
# Versions pinned to LFS 12.1.
# Source: https://www.linuxfromscratch.org/lfs/view/12.1/
# MD5 checksums from the LFS 12.1 md5sums file (published by the book).
# Toolchain-shared packages (GCC, Glibc, Binutils, GMP, MPFR, MPC, M4, File,
# XZ, and the other Ch.6 packages) reuse the vars defined above — no _CH8_
# duplicates needed since LFS 12.1 uses the same versions in Ch.5-6 and Ch.8.

MAN_PAGES_VERSION=6.06
MAN_PAGES_URL="https://www.kernel.org/pub/linux/docs/man-pages/man-pages-${MAN_PAGES_VERSION}.tar.xz"
MAN_PAGES_MD5=26b39e38248144156d437e1e10cb20bf

IANA_ETC_VERSION=20240125
IANA_ETC_URL="https://github.com/Mic92/iana-etc/releases/download/${IANA_ETC_VERSION}/iana-etc-${IANA_ETC_VERSION}.tar.gz"
IANA_ETC_MD5=aed66d04de615d76c70890233081e584

# Ch.8 glibc: same version as Ch.5 cross-build (GLIBC_VERSION=2.39).
# Reuse GLIBC_URL. Additional patch and tzdata for the Ch.8 install:
GLIBC_PATCH_URL="https://www.linuxfromscratch.org/patches/lfs/12.1/glibc-${GLIBC_VERSION}-fhs-1.patch"
GLIBC_PATCH_MD5=9a5997c3452909b1769918c759eff8a2

TZDATA_VERSION=2024a
TZDATA_URL="https://www.iana.org/time-zones/repository/releases/tzdata${TZDATA_VERSION}.tar.gz"
TZDATA_MD5=2349edd8335245525cc082f2755d5bf4

ZLIB_VERSION=1.3.1
ZLIB_URL="https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz"
ZLIB_MD5=9855b6d802d7fe5b7bd5b196a2271655

BZIP2_VERSION=1.0.8
BZIP2_URL="https://www.sourceware.org/pub/bzip2/bzip2-${BZIP2_VERSION}.tar.gz"
BZIP2_MD5=67e051268d0c475ea773822f7500d0e5
BZIP2_PATCH_URL="https://www.linuxfromscratch.org/patches/lfs/12.1/bzip2-${BZIP2_VERSION}-install_docs-1.patch"
BZIP2_PATCH_MD5=6a5ac7e89b791aae556de0f745916f7f

# Ch.8 XZ: same version as Ch.6 cross-build (XZ_VERSION=5.4.6). Reuse XZ_URL.
# (No _CH8_ suffix needed — same tarball.)

ZSTD_VERSION=1.5.5
ZSTD_URL="https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"
ZSTD_MD5=63251602329a106220e0a5ad26ba656f

# Ch.8 File: same version as Ch.6 cross-build (FILE_VERSION=5.45). Reuse FILE_URL.

READLINE_VERSION=8.2
READLINE_URL="https://ftp.gnu.org/gnu/readline/readline-${READLINE_VERSION}.tar.gz"
READLINE_MD5=4aa1b31be779e6b84f9a96cb66bc50f6
READLINE_PATCH_URL="https://www.linuxfromscratch.org/patches/lfs/12.1/readline-8.2-upstream_fixes-3.patch"
READLINE_PATCH_MD5=9ed497b6cb8adcb8dbda9dee9ebce791

# Ch.8 M4: same version as Ch.6 cross-build (M4_VERSION=1.4.19). Reuse M4_URL.

BC_VERSION=6.7.5
BC_URL="https://github.com/gavinhoward/bc/releases/download/${BC_VERSION}/bc-${BC_VERSION}.tar.xz"
BC_MD5=e249b1f86f886d6fb71c15f72b65dd3d

FLEX_VERSION=2.6.4
FLEX_URL="https://github.com/westes/flex/releases/download/v${FLEX_VERSION}/flex-${FLEX_VERSION}.tar.gz"
FLEX_MD5=2882e3179748cc9f9c23ec593d6adc8d

TCL_VERSION=8.6.13
TCL_URL="https://downloads.sourceforge.net/tcl/tcl${TCL_VERSION}-src.tar.gz"
TCL_MD5=0e4358aade2f5db8a8b6f2f6d9481ec2

EXPECT_VERSION=5.45.4
EXPECT_URL="https://prdownloads.sourceforge.net/expect/expect${EXPECT_VERSION}.tar.gz"
EXPECT_MD5=00fce8de158422f5ccd2666512329bd2
# No patch for expect in LFS 12.1 (the gcc15 patch is a 12.2+ addition)

DEJAGNU_VERSION=1.6.3
DEJAGNU_URL="https://ftp.gnu.org/gnu/dejagnu/dejagnu-${DEJAGNU_VERSION}.tar.gz"
DEJAGNU_MD5=68c5208c58236eba447d7d6d1326b821

PKGCONF_VERSION=2.1.1
PKGCONF_URL="https://distfiles.ariadne.space/pkgconf/pkgconf-${PKGCONF_VERSION}.tar.xz"
PKGCONF_MD5=bc29d74c2483197deb9f1f3b414b7918

# Ch.8 Binutils: same version as Ch.5 cross-build (BINUTILS_VERSION=2.42). Reuse BINUTILS_URL.
# Ch.8 GMP: same version as Ch.5 (GMP_VERSION=6.3.0). Reuse GMP_URL.
# Ch.8 MPFR: same version as Ch.5 (MPFR_VERSION=4.2.1). Reuse MPFR_URL.
# Ch.8 MPC: same version as Ch.5 (MPC_VERSION=1.3.1). Reuse MPC_URL.

ATTR_VERSION=2.5.2
ATTR_URL="https://download.savannah.gnu.org/releases/attr/attr-${ATTR_VERSION}.tar.gz"
ATTR_MD5=227043ec2f6ca03c0948df5517f9c927

ACL_VERSION=2.3.2
ACL_URL="https://download.savannah.gnu.org/releases/acl/acl-${ACL_VERSION}.tar.xz"
ACL_MD5=590765dee95907dbc3c856f7255bd669

LIBCAP_VERSION=2.69
LIBCAP_URL="https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-${LIBCAP_VERSION}.tar.xz"
LIBCAP_MD5=4667bacb837f9ac4adb4a1a0266f4b65

LIBXCRYPT_VERSION=4.4.36
LIBXCRYPT_URL="https://github.com/besser82/libxcrypt/releases/download/v${LIBXCRYPT_VERSION}/libxcrypt-${LIBXCRYPT_VERSION}.tar.xz"
LIBXCRYPT_MD5=b84cd4104e08c975063ec6c4d0372446

SHADOW_VERSION=4.14.5
SHADOW_URL="https://github.com/shadow-maint/shadow/releases/download/${SHADOW_VERSION}/shadow-${SHADOW_VERSION}.tar.xz"
SHADOW_MD5=452b0e59f08bf618482228ba3732d0ae

# Ch.8 GCC: same version as Ch.5/6 cross-build (GCC_VERSION=13.2.0). Reuse GCC_URL.

# -- Ch.8 second half (ncurses … man-db) ------------------------------------
# These are the packages that follow GCC in LFS 12.1 Ch.8 order.
# Ch.6/Ch.7 packages reuse existing *_VERSION/*_URL vars (no duplicates).

# Ch.8 Ncurses: version 6.4-20230520 (snapshot tarball, not plain 6.4).
# Reuse NCURSES_VERSION=6.4 and NCURSES_URL already defined above.
NCURSES_MD5=c5367e829b6d9f3f97b280bb3e6bfbc3

# Ch.8 Sed: reuse SED_VERSION=4.9 / SED_URL above.
SED_MD5=6aac9b2dbafcd5b7a67a8a9bcb8036c3

PSMISC_VERSION=23.6
PSMISC_URL="https://gitlab.com/psmisc/psmisc/-/archive/v${PSMISC_VERSION}/psmisc-v${PSMISC_VERSION}.tar.gz"
PSMISC_MD5=ed3206da1184ce9e82d607dc56c52633

# Ch.8 Gettext: reuse GETTEXT_VERSION=0.22.4 / GETTEXT_URL / GETTEXT_MD5 above.

# Ch.8 Bison: reuse BISON_VERSION=3.8.2 / BISON_URL / BISON_MD5 above.

# Ch.8 Grep: reuse GREP_VERSION=3.11 / GREP_URL above.
GREP_MD5=7ffe17905ef2efc0c8f6f29693c94a99

# Ch.8 Bash: reuse BASH_VERSION=5.2.21 / BASH_URL above.
BASH_MD5=dcdabb1f8d4bb63a3e1c5c9e2b7e23f6
BASH_PATCH_URL="https://www.linuxfromscratch.org/patches/lfs/12.1/bash-5.2.21-upstream_fixes-1.patch"
BASH_PATCH_MD5=2d1691a629c558e894dbb78ee6bf34ef

LIBTOOL_VERSION=2.4.7
LIBTOOL_URL="https://ftp.gnu.org/gnu/libtool/libtool-${LIBTOOL_VERSION}.tar.xz"
LIBTOOL_MD5=2fc0b6ddcd66a89ed6e45db28fa44232

GDBM_VERSION=1.23
GDBM_URL="https://ftp.gnu.org/gnu/gdbm/gdbm-${GDBM_VERSION}.tar.gz"
GDBM_MD5=8551961e36bf8c70b7500d255d3658ec

GPERF_VERSION=3.1
GPERF_URL="https://ftp.gnu.org/gnu/gperf/gperf-${GPERF_VERSION}.tar.gz"
GPERF_MD5=9e251c0a618ad0824b51117d5d9db87e

EXPAT_VERSION=2.6.0
EXPAT_URL="https://github.com/libexpat/libexpat/releases/download/R_2_6_0/expat-${EXPAT_VERSION}.tar.xz"
EXPAT_MD5=bd169cb11f4b9bdfddadf9e88a5c4d4b

INETUTILS_VERSION=2.5
INETUTILS_URL="https://ftp.gnu.org/gnu/inetutils/inetutils-${INETUTILS_VERSION}.tar.xz"
INETUTILS_MD5=9e5a6dfd2d794dc056a770e8ad4a9263

LESS_VERSION=643
LESS_URL="https://www.greenwoodsoftware.com/less/less-${LESS_VERSION}.tar.gz"
LESS_MD5=cf05e2546a3729492b944b4874dd43dd

# Ch.8 Perl: reuse PERL_VERSION=5.38.2 / PERL_URL / PERL_MD5 above.

XML_PARSER_VERSION=2.47
XML_PARSER_URL="https://cpan.metacpan.org/authors/id/T/TO/TODDR/XML-Parser-${XML_PARSER_VERSION}.tar.gz"
XML_PARSER_MD5=89a8e82cfd2ad948b349c0a69c494463

INTLTOOL_VERSION=0.51.0
INTLTOOL_URL="https://launchpad.net/intltool/trunk/${INTLTOOL_VERSION}/+download/intltool-${INTLTOOL_VERSION}.tar.gz"
INTLTOOL_MD5=12e517cac2b57a0121cda351570f1e63

AUTOCONF_VERSION=2.72
AUTOCONF_URL="https://ftp.gnu.org/gnu/autoconf/autoconf-${AUTOCONF_VERSION}.tar.xz"
AUTOCONF_MD5=1be79f7106ab6767f18391c5e22be701

AUTOMAKE_VERSION=1.16.5
AUTOMAKE_URL="https://ftp.gnu.org/gnu/automake/automake-${AUTOMAKE_VERSION}.tar.xz"
AUTOMAKE_MD5=4017e96f89fca45ca946f1c5db6be714

KMOD_VERSION=31
KMOD_URL="https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-${KMOD_VERSION}.tar.xz"
KMOD_MD5=6165867e1836d51795a11ea4762ff66a

# Libelf comes from elfutils — only libelf is installed (not debuginfod).
ELFUTILS_VERSION=0.190
ELFUTILS_URL="https://sourceware.org/ftp/elfutils/${ELFUTILS_VERSION}/elfutils-${ELFUTILS_VERSION}.tar.bz2"
ELFUTILS_MD5=79ad698e61a052bea79e77df6a08bc4b

# Ch.8 Coreutils: reuse COREUTILS_VERSION=9.4 / COREUTILS_URL above.
COREUTILS_MD5=459e9546074db2834effe5421f250025
COREUTILS_PATCH_URL="https://www.linuxfromscratch.org/patches/lfs/12.1/coreutils-9.4-i18n-1.patch"
COREUTILS_PATCH_MD5=cca7dc8c73147444e77bc45d210229bb

CHECK_VERSION=0.15.2
CHECK_URL="https://github.com/libcheck/check/releases/download/${CHECK_VERSION}/check-${CHECK_VERSION}.tar.gz"
CHECK_MD5=50fcafcecde5a380415b12e9c574e0b2

# Ch.8 Diffutils: reuse DIFFUTILS_VERSION=3.10 / DIFFUTILS_URL above.
DIFFUTILS_MD5="" # TODO md5

# Ch.8 Gawk: reuse GAWK_VERSION=5.3.0 / GAWK_URL above.
GAWK_MD5="" # TODO md5

# Ch.8 Findutils: reuse FINDUTILS_VERSION=4.9.0 / FINDUTILS_URL above.
FINDUTILS_MD5="" # TODO md5

GROFF_VERSION=1.23.0
GROFF_URL="https://ftp.gnu.org/gnu/groff/groff-${GROFF_VERSION}.tar.gz"
GROFF_MD5=5e4f40315a22bb8a158748e7d5094c7d

GRUB_VERSION=2.12
GRUB_URL="https://ftp.gnu.org/gnu/grub/grub-${GRUB_VERSION}.tar.xz"
GRUB_MD5=60c564b1bdc39d8e43b3aab4bc0fb140

# Ch.8 Gzip: reuse GZIP_VERSION=1.13 / GZIP_URL above.
GZIP_MD5="" # TODO md5

IPROUTE2_VERSION=6.7.0
IPROUTE2_URL="https://www.kernel.org/pub/linux/utils/net/iproute2/iproute2-${IPROUTE2_VERSION}.tar.xz"
IPROUTE2_MD5=35d8277d1469596b7edc07a51470a033

KBD_VERSION=2.6.4
KBD_URL="https://www.kernel.org/pub/linux/utils/kbd/kbd-${KBD_VERSION}.tar.xz"
KBD_MD5=e2fd7adccf6b1e98eb1ae8d5a1ce5762
KBD_PATCH_URL="https://www.linuxfromscratch.org/patches/lfs/12.1/kbd-2.6.4-backspace-1.patch"
KBD_PATCH_MD5=f75cca16a38da6caa7d52151f7136895

LIBPIPELINE_VERSION=1.5.7
LIBPIPELINE_URL="https://download.savannah.gnu.org/releases/libpipeline/libpipeline-${LIBPIPELINE_VERSION}.tar.gz"
LIBPIPELINE_MD5=1a48b5771b9f6c790fb4efdb1ac71342

# Ch.8 Make: reuse MAKE_VERSION=4.4.1 / MAKE_URL above.
MAKE_MD5="" # TODO md5

# Ch.8 Patch: reuse PATCH_VERSION=2.7.6 / PATCH_URL above.
PATCH_MD5="" # TODO md5

# Ch.8 Tar: reuse TAR_VERSION=1.35 / TAR_URL above.
TAR_MD5="" # TODO md5

# Ch.8 Texinfo: reuse TEXINFO_VERSION=7.1 / TEXINFO_URL / TEXINFO_MD5 above.

VIM_VERSION=9.1.0041
VIM_URL="https://anduin.linuxfromscratch.org/LFS/vim-${VIM_VERSION}.tar.gz"
VIM_MD5=79dfe62be5d347b1325cbd5ce2a1f9b3

# Eudev — the SysV edition of this project uses eudev (not systemd-udev).
# Version 3.2.11 is the last release; sourced from GitHub.
EUDEV_VERSION=3.2.11
EUDEV_URL="https://github.com/eudev-project/eudev/releases/download/v${EUDEV_VERSION}/eudev-${EUDEV_VERSION}.tar.gz"
EUDEV_MD5="" # TODO md5
# udev-lfs helper rules tarball (same tarball used by LFS 12.1 udev/eudev installs).
UDEV_LFS_VERSION=20171102
UDEV_LFS_URL="https://anduin.linuxfromscratch.org/LFS/udev-lfs-${UDEV_LFS_VERSION}.tar.xz"
UDEV_LFS_MD5=acd4360d8a5c3ef320b9db88d275dae6

# Ch.8 Procps-ng (final, replaces ch.7 temp build).
PROCPS_VERSION=4.0.4
PROCPS_URL="https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-${PROCPS_VERSION}.tar.xz"
PROCPS_MD5=2f747fc7df8ccf402d03e375c565cf96

# Ch.8 Util-linux (final): reuse UTIL_LINUX_VERSION=2.39.3 / UTIL_LINUX_URL above.
# The final build uses different configure flags (--without-systemd added).

E2FSPROGS_VERSION=1.47.0
E2FSPROGS_URL="https://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v${E2FSPROGS_VERSION}/e2fsprogs-${E2FSPROGS_VERSION}.tar.gz"
E2FSPROGS_MD5=6b4f18a33873623041857b4963641ee9

SYSKLOGD_VERSION=1.5.1
SYSKLOGD_URL="https://www.infodrom.org/projects/sysklogd/download/sysklogd-${SYSKLOGD_VERSION}.tar.gz"
SYSKLOGD_MD5=c70599ab0d037fde724f7210c2c8d7f8

SYSVINIT_VERSION=3.08
SYSVINIT_URL="https://github.com/slicer69/sysvinit/releases/download/${SYSVINIT_VERSION}/sysvinit-${SYSVINIT_VERSION}.tar.xz"
SYSVINIT_MD5=81a05f28d7b67533cfc778fcadea168c
SYSVINIT_PATCH_URL="https://www.linuxfromscratch.org/patches/lfs/12.1/sysvinit-3.08-consolidated-1.patch"
SYSVINIT_PATCH_MD5=17ffccbb8e18c39e8cedc32046f3a475

MAN_DB_VERSION=2.12.0
MAN_DB_URL="https://download.savannah.gnu.org/releases/man-db/man-db-${MAN_DB_VERSION}.tar.xz"
MAN_DB_MD5=67e0052fa200901b314fad7b68c9db27

# -- Ch.8 prefetch list ------------------------------------------------------
# Every tarball + patch the chroot build needs. Fetched into the source cache
# OUTSIDE the chroot (network there); the in-chroot build extracts from
# /sources. Re-fetching already-cached toolchain tarballs is a no-op. Built up
# line-by-line (no continuations) so it is robust under any shell.
CH8_SOURCES="$MAN_PAGES_URL $IANA_ETC_URL $GLIBC_URL $GLIBC_PATCH_URL $TZDATA_URL"
CH8_SOURCES="$CH8_SOURCES $ZLIB_URL $BZIP2_URL $BZIP2_PATCH_URL $XZ_URL $ZSTD_URL"
CH8_SOURCES="$CH8_SOURCES $FILE_URL $READLINE_URL $READLINE_PATCH_URL $M4_URL $BC_URL"
CH8_SOURCES="$CH8_SOURCES $FLEX_URL $TCL_URL $EXPECT_URL $DEJAGNU_URL $PKGCONF_URL"
CH8_SOURCES="$CH8_SOURCES $BINUTILS_URL $GMP_URL $MPFR_URL $MPC_URL $ATTR_URL $ACL_URL"
CH8_SOURCES="$CH8_SOURCES $LIBCAP_URL $LIBXCRYPT_URL $SHADOW_URL $GCC_URL"
# Ch.7 tarballs also prefetched outside the chroot (same source cache).
CH8_SOURCES="$CH8_SOURCES $GETTEXT_URL $BISON_URL $PERL_URL $PYTHON_URL $TEXINFO_URL $UTIL_LINUX_URL"
# Ch.8 second half — ncurses … man-db.
CH8_SOURCES="$CH8_SOURCES $NCURSES_URL $PSMISC_URL $LIBTOOL_URL $GDBM_URL $GPERF_URL"
CH8_SOURCES="$CH8_SOURCES $EXPAT_URL $INETUTILS_URL $LESS_URL $XML_PARSER_URL"
CH8_SOURCES="$CH8_SOURCES $INTLTOOL_URL $AUTOCONF_URL $AUTOMAKE_URL $KMOD_URL $ELFUTILS_URL"
CH8_SOURCES="$CH8_SOURCES $COREUTILS_URL $COREUTILS_PATCH_URL $CHECK_URL $GROFF_URL"
CH8_SOURCES="$CH8_SOURCES $GRUB_URL $IPROUTE2_URL $KBD_URL $KBD_PATCH_URL"
CH8_SOURCES="$CH8_SOURCES $LIBPIPELINE_URL $VIM_URL $EUDEV_URL $UDEV_LFS_URL"
CH8_SOURCES="$CH8_SOURCES $PROCPS_URL $E2FSPROGS_URL $SYSKLOGD_URL"
CH8_SOURCES="$CH8_SOURCES $SYSVINIT_URL $SYSVINIT_PATCH_URL $MAN_DB_URL"
CH8_SOURCES="$CH8_SOURCES $BASH_PATCH_URL"
