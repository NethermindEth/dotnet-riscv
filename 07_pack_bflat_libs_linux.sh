#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/bflat-libs-linux"
file="bflat-libs-linux-musl-riscv64.zip"

cd "${TOP_DIR}"

mkdir -p "${output_dir}"

function pack_bflat_libs_linux()
{
    local file="$1"
    local output_dir="$2"
    local artifactpath="$3"

    if [ ! -d "${artifactpath}/bin/coreclr/linux.riscv64.Release/aotsdk" ] ; then
        return 1
    fi

    pushd "${artifactpath}"
        cp ./bin/coreclr/linux.riscv64.Release/aotsdk/*.a \
           ./bin/coreclr/linux.riscv64.Release/aotsdk/*.o \
           ./bin/coreclr/linux.riscv64.Release/aotsdk/*.dll \
           ./bin/runtime/net10.0-linux-Release-riscv64/*.dll \
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


pack_bflat_libs_linux "$file" "${output_dir}" "${TOP_DIR}/dotnet/artifacts" || \
pack_bflat_libs_linux "$file" "${output_dir}" "${TOP_DIR}/dotnet/src/runtime/artifacts"
