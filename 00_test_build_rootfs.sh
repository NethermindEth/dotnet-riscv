#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

tmp_dir="${TOP_DIR}/tmp/test-build-rootfs"

apt-get update -y
apt-get install -y xz-utils git debootstrap libc6-riscv64-cross qemu-user-static binfmt-support

cd "${TOP_DIR}"

mkdir -p "${tmp_dir}"

pushd "${tmp_dir}"
    git clone https://github.com/dotnet/runtime
    pushd runtime
        ./eng/common/cross/build-rootfs.sh riscv64 noble --skipemulation --skipunmount --rootfsdir $(pwd)/.tools/rootfs/riscv64
    popd
popd
exit 1
