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

# The managed ILCompiler assemblies bflat needs. The main source-build already
# produced all of them (the ILCompiler.* ones as x64 host builds under
# artifacts/bin, Microsoft.DiaSymReader from its restored NuGet package), so we
# just locate and copy them — no separate compiler build, which used to run a
# full arcade restore that could hang for the better part of an hour.
ILC_DLLS=(ILCompiler.Compiler.dll ILCompiler.RyuJit.dll ILCompiler.TypeSystem.dll
          ILCompiler.DependencyAnalysisFramework.dll ILCompiler.MetadataTransform.dll
          Microsoft.DiaSymReader.dll)

# Print the newest existing path matching the given find expression under the
# source-build tree, or nothing.
function newest()
{
    find "${TOP_DIR}/dotnet" "$@" 2>/dev/null | sort -V | tail -n1
}

# Resolve a single assembly to a concrete path, preferring the well-known
# source-build locations before falling back to a tree-wide search.
function resolve_dll()
{
    local name="$1" hit
    case "$name" in
        Microsoft.DiaSymReader.dll)
            # From the restored NuGet package; prefer a modern net* TFM.
            hit="$(newest -path '*/microsoft.diasymreader/*/lib/net[0-9]*' -name "$name")"
            [ -n "$hit" ] || hit="$(newest -path '*/microsoft.diasymreader/*' -name "$name")"
            ;;
        *)
            # x64 host build of the managed ILCompiler assemblies.
            hit="$(newest -path '*/artifacts/bin/*x64/Release*' -name "$name")"
            [ -n "$hit" ] || hit="$(newest -path '*/artifacts/bin/*' -name "$name")"
            ;;
    esac
    [ -z "$hit" ] && hit="$(newest -name "$name")"   # last resort: anywhere in the tree
    echo "$hit"
}

function pack_bflat_compiler_nupkg()
{
    local file="$1"
    local output_dir="$2"

    # Resolve every assembly up front so a missing one fails loudly.
    local -a srcs=()
    local d path
    for d in "${ILC_DLLS[@]}" ; do
        path="$(resolve_dll "$d")"
        if [ -z "$path" ] || [ ! -f "$path" ] ; then
            echo "Could not locate ${d} in the source-build output" >&2
            return 1
        fi
        echo "Using ${path}"
        srcs+=("$path")
    done

    pushd "${output_dir}"
        if [ -f "$file" ] ; then
            rm "$file"
        fi
        cp "${template_dir}/$file" ./
        unzip "$file"
        rm "$file"
    popd

    cp "${srcs[@]}" "${output_dir}/lib/net6.0/"

    ret="1"
    pushd "${output_dir}"
        zip -r "$file" *
        ret="$?"
    popd

    return $ret
}


pack_bflat_compiler_nupkg "$file" "${output_dir}"
exit $ret
