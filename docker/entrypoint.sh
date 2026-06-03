#!/bin/bash
# Container entrypoint. Sets up the LFS env, then executes the command.

set -e

export LFS="${LFS:-/mnt/lfs}"
export LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
export STUDENT_LOGIN="${STUDENT_LOGIN:-dlesieur}"
export KERNEL_VERSION="${KERNEL_VERSION:-6.6.32}"

# Sanity: /project must be mounted read-only and /output writable.
if [[ ! -d /project ]]; then
    echo "FATAL: /project not mounted. Run via 'make' from the project root." >&2
    exit 1
fi
if [[ ! -d /output ]]; then
    echo "FATAL: /output not mounted." >&2
    exit 1
fi

mkdir -p /output/logs

exec "$@"
