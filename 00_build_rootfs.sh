#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

tmp_dir="${TOP_DIR}/tmp/rootfs"

apt-get update -y
apt-get install -y xz-utils git debootstrap libc6-riscv64-cross qemu-user-static binfmt-support python3-pip \
                   gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu
pip3 install aiohttp

cd "${TOP_DIR}"

mkdir -p "${tmp_dir}"

pushd "${tmp_dir}"
    git clone https://github.com/dotnet/runtime
    pushd runtime
        echo Preparing GNU rootfs
        ./eng/common/cross/build-rootfs.sh riscv64 noble --skipemulation --skipunmount --rootfsdir $(pwd)/.tools/rootfs/riscv64-gnu
        echo Preparing musl rootfs
        ./eng/common/cross/build-rootfs.sh riscv64 alpineedge --skipemulation --skipunmount --rootfsdir $(pwd)/.tools/rootfs/riscv64-musl
        # The Alpine feed ships musl built for rv64gc (compressed + atomic
        # instructions). The zkVM guest decodes only base rv64im, so rebuild
        # musl for rv64im from the same aport and overwrite the stock libc.a +
        # crt in the musl rootfs; 04_pack_libs.sh then packs the clean copy.
        echo Rebuilding musl for rv64im
        "${TOP_DIR}/build_musl_rv64im.sh" "$(pwd)/.tools/rootfs/riscv64-musl/usr/lib"
    popd
popd
