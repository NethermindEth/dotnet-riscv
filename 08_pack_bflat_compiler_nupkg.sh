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
        # bflat consumes the *managed* ILCompiler assemblies as a library, and they
        # are portable: the RISC-V target is selected at runtime (--targetarch),
        # so there is nothing arch-specific to build.
        # Build only the managed ILCompiler.RyuJit project graph — no native cross
        # build, no rootfs, and crucially no self-contained ILCompiler/crossgen2
        # publish, which would try to restore the unofficial linux-musl-riscv64
        # runtime packs (NU1101/NU1102). It restores from public feeds only.
        ./build.sh --restore --build \
                   --projects "$(pwd)/src/coreclr/tools/aot/ILCompiler.RyuJit/ILCompiler.RyuJit.csproj" \
                   -c Release
    popd
}

function pack_bflat_compiler_nupkg()
{
    local file="$1"
    local output_dir="$2"
    local artifactpath="$3"

    # The ProjectReference build drops every managed assembly bflat needs into
    # ILCompiler.RyuJit's output. Locate it via find so the config/rid-specific
    # subdirectory is not hardcoded.
    local ilc_out
    ilc_out="$(dirname "$(find "${artifactpath}/bin" -path '*ILCompiler.RyuJit*' -name ILCompiler.Compiler.dll 2>/dev/null | head -1)")"
    if [ ! -f "${ilc_out}/ILCompiler.Compiler.dll" ] ; then
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

    cp "${ilc_out}/ILCompiler.Compiler.dll" \
       "${ilc_out}/ILCompiler.RyuJit.dll" \
       "${ilc_out}/ILCompiler.TypeSystem.dll" \
       "${ilc_out}/ILCompiler.DependencyAnalysisFramework.dll" \
       "${ilc_out}/ILCompiler.MetadataTransform.dll" \
       "${ilc_out}/Microsoft.DiaSymReader.dll" \
       "${output_dir}/lib/net6.0/"

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
