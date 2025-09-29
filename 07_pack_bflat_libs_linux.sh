#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/bflat-libs-linux"
file="bflat-libs-linux-musl-riscv64.zip"

apt-get update -y
apt-get install -y gcc-riscv64-linux-gnu

cd "${TOP_DIR}"

mkdir -p "${output_dir}"

function pack_bflat_libs_linux()
{
    local file="$1"
    local output_dir="$2"
    local artifactpath="$3"
    local pkgpath=".packages/microsoft.netcore.app.runtime.nativeaot.linux-riscv64/10.0.0-preview.7.25377.199/runtimes/linux-riscv64"

    if [ ! -d "${artifactpath}/bin/coreclr/linux.riscv64.Release/aotsdk" ] ; then
        return 1
    fi

    pushd "${artifactpath}/$pkgpath"
        cp ./lib/net10.0/*.dll \
           ./native/*.a \
           ./native/*.o \
           ./native/*.so \
           ./native/*.dll \
           "${output_dir}/"
    popd

    ret="$?"
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


pack_bflat_libs_linux "$file" "${output_dir}" "${TOP_DIR}/dotnet"

exit $?