# ft_linux build environment
# Debian 12 + the LFS host-system requirements.
# Reference: https://www.linuxfromscratch.org/lfs/view/stable/chapter02/hostreqs.html
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C \
    LANG=C

# LFS host requirements + tools we need for partition/loop/chroot/grub work.
# Keep this list close to scripts/install_deps.sh so the two stay in sync.
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash binutils bison coreutils diffutils findutils gawk gcc g++ \
        grep gzip m4 make patch perl python3 sed tar texinfo xz-utils \
        bc file flex gettext autoconf automake libtool pkg-config \
        bzip2 cpio kmod \
        wget curl ca-certificates \
        parted dosfstools e2fsprogs util-linux fdisk gdisk \
        mount kpartx \
        grub-pc-bin grub-common xorriso \
        rsync git ncurses-dev libssl-dev libelf-dev \
        sudo procps less vim-tiny && \
    rm -rf /var/lib/apt/lists/*

# An unprivileged "lfs" user is recommended by the book for the toolchain
# phase. We keep root available for the chroot phase via sudo NOPASSWD.
RUN groupadd -r lfs && \
    useradd -m -s /bin/bash -g lfs lfs && \
    echo 'lfs ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/lfs

# /mnt/lfs is the LFS build root, persisted via a named docker volume.
RUN mkdir -p /mnt/lfs && chown lfs:lfs /mnt/lfs

# /project is the read-only mount of our source tree.
# /output is the read-write mount where the disk image lands.
WORKDIR /project

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
