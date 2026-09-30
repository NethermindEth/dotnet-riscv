#!/bin/bash

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

# Fixup profile: "minimal" (default) applies only the correctness fixups;
# "perf" additionally applies the riscv64 code-quality fixups on top.
# "upstream" is standalone: only the patches staged for submission to
# dotnet/runtime (the numbered NN_*.patch files), so that the subset is
# proven to apply and build on its own. "upstream-perf" adds the downstream
# riscv64 code-quality patches kept next to them as perf-*.patch; those are
# zkVM-specific and never meant for submission.
profile="${1:-minimal}"

# The runtime tree to patch: the VMR's copy by default, or a plain dotnet/runtime
# checkout (runtime_tests.sh builds the tests from one).
runtime_dir="${RUNTIME_DIR:-dotnet/src/runtime}"

# Each entry is <dir>:<glob>; globs are applied in order within a dir.
case "$profile" in
    minimal)
        profile_sets="minimal:*.patch"
        ;;
    perf|performance)
        profile_sets="minimal:*.patch perf:*.patch"
        ;;
    upstream)
        profile_sets="upstream:[0-9]*.patch"
        ;;
    upstream-perf)
        profile_sets="upstream:[0-9]*.patch upstream:perf-*.patch"
        ;;
    none)
        # Nothing applied: the baseline the other profiles are compared with.
        profile_sets=""
        ;;
    *)
        echo "Unknown fixup profile: $profile (expected minimal, perf, upstream, upstream-perf or none)" >&2
        exit 1
        ;;
esac

if [ ! -d "$runtime_dir" ] ; then
    echo "$runtime_dir not found: the cloned VMR branch has no runtime sources." >&2
    echo "SDK-only feature bands (e.g. release/10.0.3xx/4xx) cannot source-build the runtime;" >&2
    echo "use a full-VMR ref such as release/10.0.1xx or a vN.n.nnn tag." >&2
    exit 1
fi

# Fixups are versioned per .NET major (fixup/<major>/profile/<profile>).
major="$(sed -n 's/.*<MajorVersion>\([0-9][0-9]*\)<\/MajorVersion>.*/\1/p' "$runtime_dir/eng/Versions.props" | head -n1)"
if [ -z "$major" ] ; then
    echo "Cannot determine the .NET major version from $runtime_dir/eng/Versions.props" >&2
    exit 1
fi
echo "Detected .NET major version: $major"

for set in $profile_sets ; do
    dir="${set%%:*}"
    if [ ! -d "${TOP_DIR}/fixup/$major/profile/$dir" ] ; then
        echo "No '$dir' fixups for .NET $major (fixup/$major/profile/$dir does not exist)." >&2
        exit 1
    fi
done

pushd "$runtime_dir"
    for set in $profile_sets ; do
        dir="${set%%:*}"
        glob="${set#*:}"
        for file in $(ls ${TOP_DIR}/fixup/$major/profile/$dir/$glob | xargs) ; do
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

# The patches add JIT helpers and a JIT flag, so the JIT/EE contract differs from
# what upstream shipped and the GUID has to be rewritten. It is not done in a
# patch: a patch names the old value, and upstream rolls that value constantly,
# so it would stop applying on the next VMR bump.
if [ -n "$profile_sets" ] ; then
    "${TOP_DIR}/bump_jitee_guid.sh" "$runtime_dir"
fi
