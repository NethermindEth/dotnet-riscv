#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/crossrootfs-linux"
file="crossrootfs-musl-riscv64.tar.xz"

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

pack_crossrootfs "$file" "${output_dir}" "${TOP_DIR}/dotnet/crossrootfs/riscv64" || \
pack_crossrootfs "$file" "${output_dir}" "${TOP_DIR}/dotnet/src/runtime/crossrootfs/riscv64"
