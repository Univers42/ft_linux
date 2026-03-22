#!/bin/sh

set -e

echo "Updating system..."
sudo apt update

echo "Installing dependencies..."

sudo apt install -y \
acl \
attr \
autoconf \
automake \
bash \
bc \
binutils \
bison \
bzip2 \
check \
coreutils \
dejagnu \
diffutils \
e2fsprogs \
expat \
expect \
file \
findutils \
flex \
gawk \
gcc \
gettext \
gperf \
grep \
groff \
grub-pc \
gzip \
inetutils-tools \
intltool \
iproute2 \
kbd \
kmod \
less \
libcap2 \
libpipeline1 \
libtool \
m4 \
make \
man-db \
manpages \
libmpc-dev \
libmpfr-dev \
libgmp-dev \
ncurses-bin \
patch \
perl \
pkg-config \
procps \
psmisc \
readline-common \
sed \
tar \
tcl \
texinfo \
tzdata \
udev \
util-linux \
vim \
libxml-parser-perl \
xz-utils \
zlib1g

echo "Done!"