#!/bin/bash
# Applies the riscv64 ISA/ABI toolchain patch to every copy of
# eng/common/cross/toolchain.cmake in the VMR.
#
# patch_runtime.sh only patches dotnet/src/runtime, but the VMR carries ~23
# copies of eng/common (one per repository plus the root), and the copy the
# native build ends up reading is not the one under src/runtime. Patching a
# single copy silently does nothing: the build still configures with the stock
# toolchain file, and the first cmake probe fails against a sysroot whose ABI it
# was not told about.
#
# Mirrors what patch_alpine.sh does for build-rootfs.sh.
set -u

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

profile="${1:-upstream}"

if [ ! -d dotnet/src/runtime ] ; then
    echo "dotnet/src/runtime not found" >&2
    exit 1
fi

major="$(sed -n 's/.*<MajorVersion>\([0-9][0-9]*\)<\/MajorVersion>.*/\1/p' dotnet/src/runtime/eng/Versions.props | head -n1)"
[ -n "$major" ] || { echo "cannot determine the .NET major version" >&2; exit 1; }

# The toolchain hunk lives in whichever patch of the profile touches it.
patch_file="$(grep -l 'eng/common/cross/toolchain.cmake' "${TOP_DIR}/fixup/${major}/profile/${profile}"/*.patch 2>/dev/null | head -n1)"
if [ -z "$patch_file" ] ; then
    echo "No toolchain patch in fixup/${major}/profile/${profile}; nothing to do."
    exit 0
fi
echo "Toolchain patch: $patch_file"

# Only the toolchain.cmake section of that patch: the other copies of eng/common
# in the VMR do not carry the rest of the files the patch may touch.
section="$(mktemp)"
trap 'rm -f "$section"' EXIT
awk '
    /^diff --git / { keep = ($0 ~ /eng\/common\/cross\/toolchain\.cmake/) }
    keep { print }
' "$patch_file" > "$section"
if ! grep -q '^diff --git' "$section" ; then
    echo "No toolchain.cmake section found in $patch_file" >&2
    exit 1
fi

applied=0
skipped=0
while IFS= read -r f ; do
    dir="${f%/eng/common/cross/toolchain.cmake}"
    if grep -q 'CLR_CMAKE_RISCV64_MARCH' "$f" ; then
        skipped=$((skipped + 1))
        continue
    fi
    if (cd "$dir" && patch -p1 --forward --no-backup-if-mismatch --silent < "$section") ; then
        applied=$((applied + 1))
    else
        echo "Failed to apply the toolchain patch in $dir" >&2
        exit 1
    fi
done < <(find dotnet -path '*/eng/common/cross/toolchain.cmake' -not -path '*/node_modules/*')

echo "toolchain.cmake patched: $applied, already patched: $skipped"
if [ "$applied" = 0 ] && [ "$skipped" = 0 ] ; then
    echo "No eng/common/cross/toolchain.cmake found under dotnet - the VMR layout changed?" >&2
    exit 1
fi
