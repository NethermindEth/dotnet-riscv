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

        # The stage-one toolset restore (Arcade.Sdk & friends, stamped with our
        # OfficialBuildId) is not on any public feed for preview bands, and it
        # goes through NuGet.config — not RestoreAdditionalProjectSources — so
        # register the VMR's own package outputs (Shipping, NonShipping and the
        # .packages cache; Arcade lives under NonShipping) as NuGet sources.
        # Inserted right after the <clear /> that opens <packageSources>; a
        # source added before that clear would be wiped, and the file has an
        # unrelated <clear /> in <fallbackPackageFolders>.
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

        # The unofficial linux-musl-riscv64 runtime/host/crossgen2 packs are not
        # on any public NuGet feed (for preview bands their exact versions do not
        # exist publicly at all), but the main source-build already produced them
        # locally. Point the stage-one restore at that output so it resolves them
        # instead of failing with NU1101/NU1102.
        # %3B is an escaped ';' — MSBuild otherwise reads the ';' as a property
        # separator (turning the second path into an invalid property, MSB1006).
        local local_packs="${TOP_DIR}/dotnet/artifacts/packages/Release/Shipping/runtime"
        local_packs+="%3B${TOP_DIR}/dotnet/artifacts/packages/Release/Shipping/aspnetcore"

        # This stand-alone stage-one build runs against a bootstrap .NET SDK of
        # the SAME major band as what we build. Because that SDK already knows the
        # current TFM, the runtime repo's targetingpacks.targets override (which
        # would stamp the live $(ProductVersion) onto the packs) is skipped, and
        # the self-contained AOT-tool publishes resolve their runtime/apphost/
        # NativeAOT/AspNetCore packs at the bootstrap SDK's bundled version. Those
        # RID-specific preview packs were never published, so restore fails NU1102
        # while only the outer VMR's version exists (and is exposed via the feeds
        # above). Pinning -p:ProductVersion does NOT help — the bootstrap SDK's
        # KnownFrameworkReference wins over it.
        #
        # Read the version the VMR actually shipped off the host pack filename and
        # force every framework pack onto it via an injected targets file
        # (CustomAfterMicrosoftCommonTargets), which rewrites the same
        # KnownFrameworkReference/KnownRuntimePack metadata targetingpacks.targets
        # would — unconditionally, so it beats the bootstrap SDK.
        local vmr_version="" host_pkg
        host_pkg=$(ls "${TOP_DIR}/dotnet/artifacts/packages/Release/Shipping/runtime/Microsoft.NETCore.App.Host.linux-musl-riscv64."*.nupkg 2>/dev/null | head -n1)
        if [ -n "${host_pkg}" ]; then
            vmr_version=$(basename "${host_pkg}")
            vmr_version=${vmr_version#Microsoft.NETCore.App.Host.linux-musl-riscv64.}
            vmr_version=${vmr_version%.nupkg}
        fi

        # NB: pass the version only through the injected targets file, NOT as a
        # global -p:RuntimeFrameworkVersion — a global would also retarget the
        # host-side tools (which run on x64 and need the bootstrap SDK's public
        # x64 packs) and break their restore. The targets file scopes the pin to
        # riscv64 projects.
        local version_args=()
        if [ -n "${vmr_version}" ]; then
            version_args=(
                -p:CustomAfterMicrosoftCommonTargets="${TOP_DIR}/tools/pin_framework_pack_version.targets"
                -p:PinFrameworkPackVersion="${vmr_version}"
            )
            echo "Pinning stage-one riscv64 framework packs to ${vmr_version}"
        else
            echo "WARNING: could not determine VMR framework-pack version; stage-one restore may fail" >&2
        fi

        ./build.sh -s clr+clr.aot+clr.tools \
                   -c Release \
                   -rc Release \
                   -os linux-musl \
                   --targetrid linux-musl-riscv64 \
                   -arch riscv64 \
                   -cross \
                   -p:StageOneBuild=true \
                   -p:RestoreAdditionalProjectSources="${local_packs}" \
                   "${version_args[@]}"
    popd
}

# Locate a freshly-built managed assembly under the stage-one artifacts and echo
# its path. These are pure managed (AnyCPU) assemblies produced by the managed
# ILCompiler build, so they exist whenever that build reached them — independent
# of the (unneeded, and for riscv64 currently failing) native `ilc` link. Prefer
# the assembly's own project output dir, then fall back to any riscv64 Release
# output (the projects copy each other's assemblies), never an obj/ intermediate.
function find_fresh_managed_dll()
{
    local base="$1" art="$2"
    local proj="${base%.dll}"
    local direct="${art}/bin/${proj}/riscv64/Release/${base}"

    if [ -f "${direct}" ] ; then
        printf '%s\n' "${direct}"
        return 0
    fi
    find "${art}/bin" -type f -name "${base}" -path '*/riscv64/Release/*' \
         ! -path '*/obj/*' 2>/dev/null | head -n1
}

function pack_bflat_compiler_nupkg()
{
    local file="$1"
    local output_dir="$2"
    local artifactpath="$3"
    local libdir="${output_dir}/lib/net6.0"

    # Lay down the template so we inherit its .nuspec and layout, then overwrite
    # every assembly it carries with the freshly built one. The template ships a
    # .NET 10 ILCompiler; if any refresh below is skipped we would silently
    # re-ship that stale compiler (the historical bug: a wrong guard let a failed
    # build pack the pristine template and exit 0), so a missing assembly is a
    # hard failure here, never a fallback to the template copy.
    pushd "${output_dir}"
        if [ -f "$file" ] ; then
            rm "$file"
        fi
        cp "${template_dir}/$file" ./
        unzip -o "$file"
        rm "$file"
    popd

    local dll base src missing=0 refreshed=0

    # Every ILCompiler*.dll the template carries must be replaced with the fresh
    # build — these hold the types bflat compiles against (TypeSystem, Compiler,
    # RyuJit, ...). Refreshing exactly the template's set keeps the curated
    # assembly list while guaranteeing the bits are the ones we just built.
    for dll in "${libdir}"/ILCompiler*.dll ; do
        [ -e "$dll" ] || continue
        base=$(basename "$dll")
        src=$(find_fresh_managed_dll "$base" "$artifactpath")
        if [ -n "$src" ] && [ -f "$src" ] ; then
            cp -f "$src" "$dll"
            refreshed=$((refreshed + 1))
        else
            echo "ERROR: no freshly-built ${base} found under ${artifactpath}/bin" >&2
            missing=$((missing + 1))
        fi
    done

    # DiaSymReader is a stable, version-tolerant dependency (not one of the
    # types bflat fails on); refresh it if the build produced one, otherwise keep
    # the template's copy rather than failing the whole pack.
    src=$(find_fresh_managed_dll "Microsoft.DiaSymReader.dll" "$artifactpath")
    if [ -n "$src" ] && [ -f "$src" ] ; then
        cp -f "$src" "${libdir}/Microsoft.DiaSymReader.dll"
    fi

    if [ "$refreshed" -eq 0 ] || [ "$missing" -ne 0 ] ; then
        echo "ERROR: refusing to pack ${file} — ${missing} ILCompiler assembly(ies) missing," \
             "${refreshed} refreshed; this would ship the stale .NET 10 template compiler." >&2
        echo "Freshly-built ILCompiler assemblies available under ${artifactpath}/bin:" >&2
        find "${artifactpath}/bin" -type f -name 'ILCompiler*.dll' \
             -path '*/riscv64/Release/*' ! -path '*/obj/*' 2>/dev/null | sort -u >&2
        ret="1"
        return 1
    fi

    echo "Refreshed ${refreshed} ILCompiler assembly(ies) from the stage-one build."

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
