#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/bflat-libs-linux"
file="bflat-libs-linux-${LIBC}-${ARCH}.zip"

apt-get update -y
if [ "${ARCH}" == "riscv64" ] ; then
    apt-get install -y gcc-riscv64-linux-gnu
else
    apt-get install -y build-essential
fi

cd "${TOP_DIR}"

mkdir -p "${output_dir}"

function pack_bflat_libs_linux()
{
    local file="$1"
    local output_dir="$2"
    local artifactpath="$3"
    local pkgpath=".packages/microsoft.netcore.app.runtime.nativeaot.linux-${LIBC}-${ARCH}"

    if [ ! -d "${artifactpath}/$pkgpath" ] ; then
        return 1
    fi

    pushd "${artifactpath}/$pkgpath"
        cp 10.0.0*/runtimes/linux-*${ARCH}/lib/net10.0/*.dll \
           10.0.0*/runtimes/linux-*${ARCH}/native/*.a \
           10.0.0*/runtimes/linux-*${ARCH}/native/*.o \
           10.0.0*/runtimes/linux-*${ARCH}/native/*.so \
           10.0.0*/runtimes/linux-*${ARCH}/native/*.dll \
           "${output_dir}/"
    popd

    ret="$?"
    pushd "${output_dir}"
        if [ -f "$file" ] ; then
            rm "$file"
        fi
        if [ "${ARCH}" == "riscv64" ] ; then
            riscv64-linux-gnu-strip --strip-debug *.a *.o
        else
            strip --strip-debug *.a *.o
        fi
        zip -r "$file" *
        ret="$?"
    popd

    return $ret
}


pack_bflat_libs_linux "$file" "${output_dir}" "${TOP_DIR}/dotnet"

exit $?