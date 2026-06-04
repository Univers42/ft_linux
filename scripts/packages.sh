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
