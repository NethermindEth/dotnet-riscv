#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/libs-linux"
gnu_output_dir="${TOP_DIR}/output/gnu-libs-linux"
file="libs-linux-musl-riscv64.zip"

cd "${TOP_DIR}"

mkdir -p "${output_dir}"

function pack_libs()
{
    local file="$1"
    local output_dir="$2"
    local crosspath="$3"

    if [ ! -d "${crosspath}" ] ; then
        return 1
    fi

    pushd "${crosspath}"
        cp ./usr/lib/*.a \
           ./usr/lib/*.o \
           ./usr/lib/gcc/riscv64-alpine-linux-musl/14.3.0/libgcc.a \
           "${gnu_output_dir}/libatomic.a" \
           "${output_dir}/"
    popd

    pushd "${output_dir}"
        if [ -f "$file" ] ; then
            rm "$file"
        fi
        zip -r "$file" *
    popd

    return 0
}


pack_libs "$file" "${output_dir}" "${TOP_DIR}/dotnet/crossrootfs/riscv64" || \
pack_libs "$file" "${output_dir}" "${TOP_DIR}/dotnet/src/runtime/crossrootfs/riscv64"
