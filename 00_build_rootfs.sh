#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

tmp_dir="${TOP_DIR}/tmp/rootfs"

apt-get update -y
apt-get install -y xz-utils git debootstrap libc6-riscv64-cross qemu-user-static binfmt-support python3-pip \
                   gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu
pip3 install aiohttp

cd "${TOP_DIR}"

. "${TOP_DIR}/alpine_mirror.sh"

mkdir -p "${tmp_dir}"

pushd "${tmp_dir}"
    git clone https://github.com/dotnet/runtime
    pushd runtime
        # Custom rv64ima Alpine rootfs: package trimming + the bflat-hosted
        # mirror (see patch_alpine.sh). Kept downstream only, and only needed
        # for the soft-float target - a stock lp64d build wants the stock
        # userspace. SOFT_FLOAT_ROOTFS=false selects that.
        if [ "${SOFT_FLOAT_ROOTFS:-true}" = "true" ] ; then
            patch -p1 < "${TOP_DIR}/fixup/rootfs/alpine_custom.patch"
            substitute_alpine_mirror eng/common/cross/build-rootfs.sh
        fi
        echo Preparing GNU rootfs
        ./eng/common/cross/build-rootfs.sh riscv64 noble --skipemulation --skipunmount --rootfsdir $(pwd)/.tools/rootfs/riscv64-gnu
        echo Preparing musl rootfs
        ./eng/common/cross/build-rootfs.sh riscv64 alpineedge --skipemulation --skipunmount --rootfsdir $(pwd)/.tools/rootfs/riscv64-musl
        if [ "${SOFT_FLOAT_ROOTFS:-true}" = "true" ] ; then
            # The mirror's musl is built for rv64ima: its locks carry lr/sc.
            # The zkVM guest decodes only base rv64im, so rebuild musl for
            # rv64im from the same aport and overwrite the stock libc.a + crt
            # in the musl rootfs; the pack steps then pick up the clean copy.
            echo Rebuilding musl for rv64im
            "${TOP_DIR}/build_musl_rv64im.sh" "$(pwd)/.tools/rootfs/riscv64-musl/usr/lib"
        fi
    popd
popd
