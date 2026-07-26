#!/bin/bash

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

# Fixup profile: "minimal" (default) applies only the correctness fixups;
# "perf" additionally applies the riscv64 code-quality fixups on top.
profile="${1:-minimal}"

case "$profile" in
    minimal)
        profile_dirs="minimal"
        ;;
    perf|performance)
        profile_dirs="minimal perf"
        ;;
    *)
        echo "Unknown fixup profile: $profile (expected minimal or perf)" >&2
        exit 1
        ;;
esac

if [ ! -d dotnet/src/runtime ] ; then
    echo "dotnet/src/runtime not found: the cloned VMR branch has no runtime sources." >&2
    echo "SDK-only feature bands (e.g. release/10.0.3xx/4xx) cannot source-build the runtime;" >&2
    echo "use a full-VMR ref such as release/10.0.1xx or a vN.n.nnn tag." >&2
    exit 1
fi

# Fixups are versioned per .NET major (fixup/<major>/profile/<profile>).
major="$(sed -n 's/.*<MajorVersion>\([0-9][0-9]*\)<\/MajorVersion>.*/\1/p' dotnet/src/runtime/eng/Versions.props | head -n1)"
if [ -z "$major" ] ; then
    echo "Cannot determine the .NET major version from dotnet/src/runtime/eng/Versions.props" >&2
    exit 1
fi
echo "Detected .NET major version: $major"

for dir in $profile_dirs ; do
    if [ ! -d "${TOP_DIR}/fixup/$major/profile/$dir" ] ; then
        echo "No '$dir' fixups for .NET $major (fixup/$major/profile/$dir does not exist)." >&2
        exit 1
    fi
done

pushd dotnet/src/runtime
    for dir in $profile_dirs ; do
        for file in $(ls ${TOP_DIR}/fixup/$major/profile/$dir/*.patch | xargs) ; do
            echo Applying $file
            patch -p1 < $file
            res="$?"
            if [ "$res" != "0" ] ; then
                echo Failed to apply patch $file >&2
                exit 1
            fi
        done
    done
popd
