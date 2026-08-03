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

        local version_args=()
        if [ -n "${vmr_version}" ]; then
            version_args=(
                -p:CustomAfterMicrosoftCommonTargets="${TOP_DIR}/tools/pin_framework_pack_version.targets"
                -p:PinFrameworkPackVersion="${vmr_version}"
                -p:RuntimeFrameworkVersion="${vmr_version}"
            )
            echo "Pinning stage-one framework packs to ${vmr_version}"
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
