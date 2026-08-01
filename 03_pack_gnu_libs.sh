#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

output_dir="${TOP_DIR}/output/gnu-libs-linux"
tmp_dir_rootfs="${TOP_DIR}/tmp/rootfs"

cd "${TOP_DIR}"

apt-get install -y xz-utils git debootstrap libc6-riscv64-cross qemu-user-static binfmt-support python3-pip \
                   gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu python3
pip3 install aiohttp

mkdir -p "${output_dir}"

# The stock GCC libatomic in the GNU rootfs is rv64gc (compressed + lr/sc) and
# the zkVM guest links libatomic but decodes only base rv64im. The guest is
# single-hart, so build our soft libatomic (plain load/modify/store, full
# __atomic_* ABI) for rv64im and pack that instead of the rv64gc one.
"${TOP_DIR}/build_libatomic_rv64im.sh" "${output_dir}"
ret="$?"

exit $ret
