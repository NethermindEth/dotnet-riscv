#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

output_dir="${TOP_DIR}/output/gnu-libs-linux"
tmp_dir="${TOP_DIR}/tmp/gnu-libs"

cd "${TOP_DIR}"

apt-get install -y xz-utils git debootstrap libc6-riscv64-cross qemu-user-static binfmt-support python3-pip
pip3 install aiohttp

mkdir -p "${output_dir}"
mkdir -p "${tmp_dir}"

apt-get update -y
apt-get install -y git debootstrap

ret="1"
pushd "${tmp_dir}"
    git clone https://github.com/dotnet/runtime
    pushd runtime
        ./eng/common/cross/build-rootfs.sh riscv64 noble --skipunmount --rootfsdir $(pwd)/.tools/rootfs/riscv64
        cp "$(pwd)/.tools/rootfs/riscv64/usr/lib/gcc/riscv64-linux-gnu/13/libatomic.a" "${output_dir}/"
        ret="0"
    popd
popd
exit $ret
