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
    local search_root="$3"

    # The x64-hosted RISC-V cross JIT (and its jitinterface) that the managed
    # ILCompiler loads to emit riscv64 code. The main build restored it into the
    # NuGet cache as part of Microsoft.NETCore.App.Crossgen2.linux-x64; find it
    # there instead of rebuilding coreclr. The riscv64 JIT only exists in the
    # freshly-built package version, so the glob self-selects the right one.
    local jit
    jit="$(find "${search_root}" -path '*crossgen2.linux-x64*/tools/libclrjit_unix_riscv64_x64.so' 2>/dev/null | head -1)"
    if [ -z "${jit}" ] ; then
        return 1
    fi
    local jit_dir
    jit_dir="$(dirname "${jit}")"

    cp "${jit_dir}/libclrjit_unix_riscv64_x64.so" \
       "${jit_dir}/libjitinterface_x64.so" \
       "${output_dir}/"

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


pack_bflat_compiler_linux "$file" "${output_dir}" "${TOP_DIR}/dotnet/.packages"

exit $?