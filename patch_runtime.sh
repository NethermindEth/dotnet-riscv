#!/bin/bash

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

# Fixup profile: "minimal" (default) applies only the correctness fixups;
# "perf" additionally applies the riscv64 code-quality fixups on top.
profile="${1:-minimal}"

case "$profile" in
    minimal)
        fixup_dirs="minimal"
        ;;
    perf|performance)
        fixup_dirs="minimal perf"
        ;;
    *)
        echo "Unknown fixup profile: $profile (expected minimal or perf)" >&2
        exit 1
        ;;
esac

pushd dotnet/src/runtime
    for dir in $fixup_dirs ; do
        for file in $(ls ${TOP_DIR}/fixup/profile/$dir/*.patch | xargs) ; do
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
