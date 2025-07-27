#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

output_dir="${TOP_DIR}/output/gnu-libs-linux"
tmp_dir_rootfs="${TOP_DIR}/tmp/rootfs"

cd "${TOP_DIR}"

apt-get install -y xz-utils git debootstrap libc6-riscv64-cross qemu-user-static binfmt-support python3-pip
pip3 install aiohttp

mkdir -p "${output_dir}"

ret="1"
pushd "${tmp_dir}"
    pushd runtime
        cp "${tmp_dir_rootfs}/runtime/.tools/rootfs/riscv64-gnu/usr/lib/gcc/riscv64-linux-gnu/13/libatomic.a" "${output_dir}/"
        ret="$?"
    popd
popd

exit $ret
