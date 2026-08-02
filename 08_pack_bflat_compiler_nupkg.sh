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

        # The unofficial linux-musl-riscv64 runtime/host/crossgen2 packs are not
        # on any public NuGet feed (for preview bands their exact versions do not
        # exist publicly at all), but the main source-build already produced them
        # locally. Point the stage-one restore at that output so it resolves them
        # instead of failing with NU1101/NU1102.
        # %3B is an escaped ';' — MSBuild otherwise reads the ';' as a property
        # separator (turning the second path into an invalid property, MSB1006).
        local local_packs="${TOP_DIR}/dotnet/artifacts/packages/Release/Shipping/runtime"
        local_packs+="%3B${TOP_DIR}/dotnet/artifacts/packages/Release/Shipping/aspnetcore"

        ./build.sh -s clr+clr.aot+clr.tools \
                   -c Release \
                   -rc Release \
                   -os linux-musl \
                   --targetrid linux-musl-riscv64 \
                   -arch riscv64 \
                   -cross \
                   -p:StageOneBuild=true \
                   -p:RestoreAdditionalProjectSources="${local_packs}"
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
        cp ./bin/coreclr/linux.riscv64.Release/ilc/ILCompiler*.dll \
           ./bin/coreclr/linux.riscv64.Release/ilc/Microsoft.DiaSymReader.dll \
           "${output_dir}/lib/net6.0/"
        cp ./bin/coreclr/linux.riscv64.Release/crossgen2/ILCompiler*.dll \
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
