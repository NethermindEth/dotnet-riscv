#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

tmp_dir="${TOP_DIR}/tmp/rootfs"

apt-get update -y
if [ "$ARCH" == "riscv64" ] ; then
    apt-get install -y xz-utils git debootstrap libc6-riscv64-cross qemu-user-static binfmt-support python3-pip
else
    apt-get install -y xz-utils git debootstrap python3-pip
fi
pip3 install aiohttp

cd "${TOP_DIR}"

mkdir -p "${tmp_dir}"

pushd "${tmp_dir}"
    git clone https://github.com/dotnet/runtime
    pushd runtime
        echo Preparing GNU rootfs
        ./eng/common/cross/build-rootfs.sh "${ARCH}" noble --skipemulation --skipunmount --rootfsdir $(pwd)/.tools/rootfs/${ARCH}-gnu
        echo Preparing musl rootfs
        ./eng/common/cross/build-rootfs.sh "${ARCH}" alpineedge --skipemulation --skipunmount --rootfsdir $(pwd)/.tools/rootfs/${ARCH}-musl
    popd
popd
