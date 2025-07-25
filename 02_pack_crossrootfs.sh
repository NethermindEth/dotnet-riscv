#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/crossrootfs-linux"
file="crossrootfs-musl-riscv64.tar.xz"

apt-get update -y
apt-get install -y xz-utils

cd "${TOP_DIR}"

mkdir -p "${output_dir}"

function pack_crossrootfs()
{
    local file="$1"
    local output_dir="$2"
    local crosspath="$3"

    if [ ! -d "${crosspath}" ] ; then
        return 1
    fi

    pushd "${crosspath}"
        tar cJf "${output_dir}/$file" *
    popd

    return 0
}

pushd "${tmp_dir}"
    git clone https://github.com/dotnet/runtime
    pushd runtime
        ./eng/common/cross/build-rootfs.sh riscv64 noble --skipunmount --rootfsdir $(pwd)/.tools/rootfs/riscv64
        cp "$(pwd)/.tools/rootfs/riscv64/usr/lib/gcc/riscv64-linux-gnu/13/libatomic.a" "${output_dir}/"
        ret="0"
    popd
popd

pack_crossrootfs "$file" "${output_dir}" "${TOP_DIR}/dotnet/.tools/rootfs/riscv64" || \
pack_crossrootfs "$file" "${output_dir}" "${TOP_DIR}/dotnet/src/runtime/.tools/rootfs/riscv64"
exit $?
