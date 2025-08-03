#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/libs-linux"
gnu_output_dir="${TOP_DIR}/output/gnu-libs-linux"

file="libs-linux-musl-riscv64.zip"
tmp_dir_rootfs="${TOP_DIR}/tmp/rootfs"

apt-get update -y
apt-get install -y gcc-riscv64-linux-gnu

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

    ret="1"
    pushd "${crosspath}"
        cp ./usr/lib/*.a \
           ./usr/lib/*.o \
           ./usr/lib/gcc/riscv64-alpine-linux-musl/*/libgcc.a \
           "${gnu_output_dir}/libatomic.a" \
           "${output_dir}/"
    popd

    pushd "${output_dir}"
        if [ -f "$file" ] ; then
            rm "$file"
        fi
        riscv64-linux-gnu-strip --strip-debug *.a *.o
        zip -r "$file" *
        ret="$?"
    popd

    return $ret
}


pack_libs "$file" "${output_dir}" "${tmp_dir_rootfs}/runtime/.tools/rootfs/riscv64-musl" || exit 1
