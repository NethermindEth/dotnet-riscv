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
    local pkgpath=".packages/microsoft.netcore.app.crossgen2.linux-x64"

    if [ ! -d "${artifactpath}/$pkgpath" ] ; then
        return 1
    fi

    pushd "${artifactpath}"
        cp $pkgpath/*/tools/libclrjit_unix_riscv64_x64.so \
           $pkgpath/*/tools/libjitinterface_x64.so \
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


pack_bflat_compiler_linux "$file" "${output_dir}" "${TOP_DIR}/dotnet"

exit $?