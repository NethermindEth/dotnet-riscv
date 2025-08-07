#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/crossrootfs-linux"
tmp_dir_rootfs="${TOP_DIR}/tmp/rootfs"

file_musl="crossrootfs-musl-${ARCH}.tar.xz"
file_gnu="crossrootfs-gnu-${ARCH}.tar.xz"

apt-get update -y
if [ "$ARCH" == "riscv64" ] ; then
    apt-get install -y xz-utils git debootstrap libc6-riscv64-cross qemu-user-static binfmt-support python3-pip
else
    apt-get install -y xz-utils git debootstrap python3-pip
fi
pip3 install aiohttp

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

pack_crossrootfs "$file_musl" "${output_dir}" "${tmp_dir_rootfs}/runtime/.tools/rootfs/${ARCH}-musl" || exit 1
pack_crossrootfs "$file_gnu" "${output_dir}" "${tmp_dir_rootfs}/runtime/.tools/rootfs/${ARCH}-gnu" || exit 2
