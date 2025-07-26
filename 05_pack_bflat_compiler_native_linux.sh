#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/bflat-compiler-native-linux"
file="bflat-compiler-native-linux-glibc-x64.zip"

cd "${TOP_DIR}"

mkdir -p "${output_dir}"

function pack_bflat_compiler_linux()
{
    local file="$1"
    local output_dir="$2"
    local artifactpath="$3"

    if [ ! -d "${artifactpath}/bin/coreclr/linux.riscv64.Release/x64" ] ; then
        return 1
    fi

    pushd "${artifactpath}"
        cp ./bin/coreclr/linux.riscv64.Release/x64/libclrjit_unix_riscv64_x64.so \
           ./bin/coreclr/linux.riscv64.Release/x64/libjitinterface_x64.so \
           "${output_dir}/"
    popd

    ret="1"
    pushd "${output_dir}"
        if [ -f "$file" ] ; then
            rm "$file"
        fi
        zip -r "$file" *
        ret="$?"
    popd

    return $ret
}


pack_bflat_compiler_linux "$file" "${output_dir}" "${TOP_DIR}/dotnet/artifacts" || \
pack_bflat_compiler_linux "$file" "${output_dir}" "${TOP_DIR}/dotnet/src/runtime/artifacts"

exit $?