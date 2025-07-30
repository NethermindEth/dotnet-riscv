#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/bflat-compiler-nupkg"
template_dir="${TOP_DIR}/template"
file="bflat.compiler.10.0.0.nupkg"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y build-essential file gettext locales cmake llvm clang lld lldb \
                   liblldb-dev libunwind8-dev libicu-dev liblttng-ust-dev libssl-dev \
                   libkrb5-dev ninja-build pigz cpio \
                   python3

cd "${TOP_DIR}"

mkdir -p "${output_dir}"

function build_compiler()
{
    local runtime_dir="$1"

    pushd "${runtime_dir}"
        export ROOTFS_DIR="$(pwd)/.tools/rootfs/riscv64-musl"
        ./eng/common/cross/build-rootfs.sh riscv64 alpineedge --skipemulation --skipunmount --rootfsdir ${ROOTFS_DIR}
        ./build.sh -s clr+clr.aot+clr.tools \
                   -c Release \
                   -rc Release \
                   -os linux-musl \
                   -arch riscv64 \
                   -cross \
                   -p:StageOneBuild=true
    popd
}

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
           ./bin/coreclr/linux.riscv64.Release/ilc/ILCompiler.RyuJit.dll \
           ./bin/crossgen2_inbuild/riscv64/Release/Microsoft.DiaSymReader.dll \
           "${output_dir}/lib/net6.0/"
    popd

    ret="1"
    pushd "${output_dir}"
        zip -r "$file" *
        ret="$?"
    popd

    return $ret
}


build_compiler "${TOP_DIR}/dotnet/src/runtime"

pack_bflat_compiler_nupkg "$file" "${output_dir}" "${TOP_DIR}/dotnet/src/runtime/artifacts"
exit $ret
