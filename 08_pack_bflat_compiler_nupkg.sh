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

# The managed ILCompiler assemblies bflat needs. All six live together in the
# published host ILCompiler (runtime.linux-x64.microsoft.dotnet.ilcompiler),
# which the main source-build already produced into .packages, so normally we
# just locate and copy them — no separate build. build_compiler() below is only
# a fallback for the rare case they are not present.
ILC_DLLS=(ILCompiler.Compiler.dll ILCompiler.RyuJit.dll ILCompiler.TypeSystem.dll
          ILCompiler.DependencyAnalysisFramework.dll ILCompiler.MetadataTransform.dll
          Microsoft.DiaSymReader.dll)

# Print a directory that contains ALL the assemblies in ILC_DLLS, or nothing.
function find_ilc_out()
{
    local dotnet_dir="$1"
    local candidate d ok f
    # Prefer the published host ILCompiler in the restored package cache (all
    # assemblies in one tools/ dir); fall back to any per-project build output.
    for candidate in \
        "${dotnet_dir}/.packages/runtime.linux-x64.microsoft.dotnet.ilcompiler" \
        "${dotnet_dir}/src/runtime/artifacts/bin"; do
        [ -d "${candidate}" ] || continue
        while IFS= read -r f; do
            d="$(dirname "$f")"
            ok=1
            for want in "${ILC_DLLS[@]}"; do
                [ -f "${d}/${want}" ] || { ok=0; break; }
            done
            if [ "${ok}" = 1 ]; then echo "${d}"; return; fi
        done < <(find "${candidate}" -name ILCompiler.Compiler.dll 2>/dev/null)
    done
}

function build_compiler()
{
    local runtime_dir="$1"

    pushd "${runtime_dir}"
        # The VMR build rewrites this repo to consume the locally built toolset
        # (arcade & friends stamped with our OfficialBuildId), which no public
        # feed carries — for released bands the versions happen to be public,
        # for preview bands they are not. Register the VMR's own package
        # outputs as NuGet sources so the restore finds them either way.
        # NB: inserted right after the <clear /> that opens <packageSources> —
        # anything added before that clear would be wiped by it, and the file
        # has another unrelated <clear /> in <fallbackPackageFolders>.
        TOP_DIR="${TOP_DIR}" python3 - <<'PYEOF'
import os, re

path = "NuGet.config"
with open(path) as f:
    s = f.read()

if "vmr-local-shipping" not in s:
    top = os.environ["TOP_DIR"]
    feeds = "\n".join(
        f'    <add key="vmr-local-{name}" value="{top}/dotnet/{sub}" />'
        for name, sub in (
            ("shipping", "artifacts/packages/Release/Shipping"),
            ("nonshipping", "artifacts/packages/Release/NonShipping"),
            ("cache", ".packages"),
        ))
    m = re.search(r"<packageSources>\s*<clear\s*/>", s)
    if m:
        s = s[:m.end()] + "\n" + feeds + s[m.end():]
    else:
        s = s.replace("<packageSources>", "<packageSources>\n" + feeds, 1)
    with open(path, "w") as f:
        f.write(s)
PYEOF

        # bflat consumes the *managed* ILCompiler assemblies as a library, and they
        # are portable: the RISC-V target is selected at runtime (--targetarch),
        # so there is nothing arch-specific to build.
        # Build only the managed ILCompiler.RyuJit project graph — no native cross
        # build, no rootfs, and crucially no self-contained ILCompiler/crossgen2
        # publish, which would try to restore the unofficial linux-musl-riscv64
        # runtime packs (NU1101/NU1102).
        ./build.sh --restore --build \
                   --projects "$(pwd)/src/coreclr/tools/aot/ILCompiler.RyuJit/ILCompiler.RyuJit.csproj" \
                   -c Release
    popd
}

function pack_bflat_compiler_nupkg()
{
    local file="$1"
    local output_dir="$2"
    local ilc_out="$3"

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

    local d
    for d in "${ILC_DLLS[@]}" ; do
        cp "${ilc_out}/${d}" "${output_dir}/lib/net6.0/"
    done

    ret="1"
    pushd "${output_dir}"
        zip -r "$file" *
        ret="$?"
    popd

    return $ret
}


# Normally the main source-build already produced the managed ILCompiler
# assemblies; only build them ourselves if they are missing.
ilc_out="$(find_ilc_out "${TOP_DIR}/dotnet")"
if [ -z "${ilc_out}" ] ; then
    echo "Managed ILCompiler assemblies not found in the source-build output; building ILCompiler.RyuJit"
    build_compiler "${TOP_DIR}/dotnet/src/runtime"
    ilc_out="$(find_ilc_out "${TOP_DIR}/dotnet")"
else
    echo "Reusing managed ILCompiler assemblies from ${ilc_out}"
fi

pack_bflat_compiler_nupkg "$file" "${output_dir}" "${ilc_out}"
exit $ret
