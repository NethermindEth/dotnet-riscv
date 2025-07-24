#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/bflat-compiler-nupkg"
template_dir="${TOP_DIR}/template"
file="bflat.compiler.10.0.0.nupkg"

cd "${TOP_DIR}"

mkdir -p "${output_dir}"

function pack_bflat_compiler_nupkg()
{
    local file="$1"
    local output_dir="$2"
    local artifactpath="$3"

    if [ ! -d "${artifactpath}/bin/ILCompiler.Compiler/riscv64/Release" ] ; then
        return 1
    fi

    pushd "${output_dir}"
        if [ -f "$file" ] ; then
            rm "$file"
        fi
        cp "${template_dir}/$file" ./
        unzip "$file"
        rm "$file"
    popd

    pushd "${artifactpath}"
        cp ./bin/ILCompiler.Compiler/riscv64/Release/ILCompiler.*.dll \
           ./bin/crossgen2_inbuild/riscv64/Release/Microsoft.DiaSymReader.dll \
           "${output_dir}/lib/net6.0/"
    popd

    pushd "${output_dir}"
        zip -r "$file" *
    popd

    return 0
}


pack_bflat_compiler_nupkg "$file" "${output_dir}" "${TOP_DIR}/dotnet/artifacts" || \
pack_bflat_compiler_nupkg "$file" "${output_dir}" "${TOP_DIR}/dotnet/src/runtime/artifacts"
