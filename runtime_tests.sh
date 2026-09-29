#!/bin/bash
# Builds the dotnet/runtime tests for linux-musl-riscv64 against a Checked
# runtime and runs them under qemu-user. It is the runtime_tests leg of
# build.yml, kept as a script so a failure can be reproduced locally with the
# same steps:
#
#   runtime_tests.sh source <vmr fork> <vmr branch> <profile>
#   runtime_tests.sh rootfs
#   runtime_tests.sh build  <coreclr|nativeaot>
#   runtime_tests.sh run    <coreclr|nativeaot>
#
# The tests come from a plain dotnet/runtime checkout at the commit the VMR
# branch pins, with the same fixup profile the SDK build applies. They are
# built the way upstream documents for platforms without published packs
# (docs/workflow/building/coreclr/cross-building.md): the product with
# --bootstrap, the tests with --use-bootstrap.
#
# SOFT_FLOAT=true selects the lp64 target: the custom Alpine rootfs, an lp64
# native build and ILC's riscv64-lp64. Only the NativeAOT tests exist for it,
# because CoreCLR itself does not support the lp64 ABI.
#
# "run" needs qemu-user registered for riscv64 through binfmt_misc with the F
# (fix-binary) flag: test runners start the test binaries as child processes,
# and those have to reach qemu too, from inside the build container.
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

RUNTIME_DIR="${TOP_DIR}/runtime"
ROOTFS="${TOP_DIR}/crossrootfs/riscv64"
IMAGE="${IMAGE:-mcr.microsoft.com/dotnet-buildtools/prereqs:azurelinux-3.0-net10.0-cross-riscv64-musl}"
SOFT_FLOAT="${SOFT_FLOAT:-false}"

# The trees the Checked NativeAOT leg of runtime.yml builds.
NATIVEAOT_TREES=";nativeaot;Loader;Interop;async;"

die()
{
    echo "$*" >&2
    exit 1
}

# Runs a command in the cross-build container. The work tree is mounted at the
# same path, so paths are the same inside and outside; QEMU_LD_PREFIX lets
# qemu-user find the musl loader of the rootfs when the tests run.
in_container()
{
    local abi_env=()
    if [ "$SOFT_FLOAT" = "true" ] ; then
        abi_env=(-e CLR_CMAKE_RISCV64_MABI=lp64 -e CLR_CMAKE_RISCV64_MARCH=rv64im -e IlcRiscV64SoftFloat=true)
    fi
    docker run --platform linux/amd64 --rm \
        "${abi_env[@]}" \
        -v "${TOP_DIR}:${TOP_DIR}" \
        -w "${RUNTIME_DIR}" \
        -e ROOTFS_DIR="${ROOTFS}" \
        -e QEMU_LD_PREFIX="${ROOTFS}" \
        -e SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
        -e FeatureXplatEventSource=false \
        "$IMAGE" "$@"
}

check_kind()
{
    case "$1" in
        coreclr)
            [ "$SOFT_FLOAT" != "true" ] || die "CoreCLR does not support the lp64 ABI: only the nativeaot tests exist for SOFT_FLOAT=true"
            ;;
        nativeaot)
            ;;
        *)
            die "Unknown test kind: $1 (expected coreclr or nativeaot)"
            ;;
    esac
}

step_source()
{
    local fork="$1" branch="$2" profile="$3" remote sha

    read -r remote sha < <(curl -fsSL "https://raw.githubusercontent.com/${fork}/dotnet/${branch}/src/source-manifest.json" |
        python3 -c 'import json, sys
r = next(r for r in json.load(sys.stdin)["repositories"] if r["path"] == "runtime")
print(r["remoteUri"], r["commitSha"])')
    echo "runtime: ${remote} at ${sha}, as pinned by ${fork}/dotnet ${branch}"

    rm -rf "${RUNTIME_DIR}"
    git init -q "${RUNTIME_DIR}"
    git -C "${RUNTIME_DIR}" fetch -q --depth 1 "${remote}" "${sha}"
    git -C "${RUNTIME_DIR}" checkout -q FETCH_HEAD

    RUNTIME_DIR="${RUNTIME_DIR}" "${TOP_DIR}/patch_runtime.sh" "${profile}"
}

step_rootfs()
{
    if [ "$SOFT_FLOAT" = "true" ] ; then
        # The same custom lp64 Alpine the SDK build uses (see patch_alpine.sh).
        . "${TOP_DIR}/alpine_mirror.sh"
        pushd "${RUNTIME_DIR}" > /dev/null
            patch -p1 < "${TOP_DIR}/fixup/rootfs/alpine_custom.patch"
            substitute_alpine_mirror eng/common/cross/build-rootfs.sh
        popd > /dev/null
    fi

    in_container ./eng/common/cross/build-rootfs.sh riscv64 alpineedge \
                                                   --skipemulation \
                                                   --skipunmount \
                                                   --rootfsdir "${ROOTFS}"

    if [ "$SOFT_FLOAT" = "true" ] ; then
        in_container "${TOP_DIR}/provision_gss_stub.sh"
    fi
}

step_build()
{
    local kind="$1" subsets tests_args=()

    check_kind "$kind"
    case "$kind" in
        coreclr)
            subsets="clr+libs"
            ;;
        nativeaot)
            subsets="clr.aot+libs.native+libs.sfx"
            tests_args=(nativeaot tree "${NATIVEAOT_TREES}")
            ;;
    esac

    in_container ./build.sh -s "${subsets}" -c Release -rc Checked \
                            --cross --arch riscv64 --os linux-musl \
                            --bootstrap /p:RunAnalyzers=false
    # No -os here: src/tests/build.sh would take "linux-musl" for the OS name and
    # look for the product under linux-musl.riscv64.Checked. Without it, the musl
    # RID is detected from the rootfs, as eng/build.sh passes it on.
    in_container ./src/tests/build.sh -cross -arch riscv64 checked \
                                      "${tests_args[@]}" \
                                      -p:LibrariesConfiguration=Release --use-bootstrap
}

step_run()
{
    local kind="$1" run_args=() binfmt=/proc/sys/fs/binfmt_misc/qemu-riscv64

    check_kind "$kind"
    [ -f "$binfmt" ] || die "qemu-user is not registered for riscv64 (${binfmt} is missing)"
    grep -q '^flags:.*F' "$binfmt" || die "qemu-riscv64 is registered without the F flag, so it is not reachable from the container"

    if [ "$kind" = "nativeaot" ] ; then
        run_args=(--runnativeaottests)
    fi

    probe "$kind"

    local rc=0
    in_container ./src/tests/run.sh riscv64 checked "${run_args[@]}" || rc=$?
    report_runners
    return $rc
}

# Starts one riscv64 binary directly, so a loader or qemu problem shows up as
# itself rather than as every test runner exiting with an unexpected code.
probe()
{
    local kind="$1" tests="${RUNTIME_DIR}/artifacts/tests/coreclr/linux.riscv64.Checked" bin

    if [ "$kind" = "nativeaot" ] ; then
        bin="$(find "${tests}" -path '*/native/*' -type f -perm -u+x ! -name '*.dbg' ! -name '*.so' | head -n1)"
    else
        bin="${tests}/Tests/Core_Root/corerun"
    fi
    echo "::group::probe: ${bin#${tests}/}"
    [ -n "$bin" ] && in_container sh -c 'head -c 20 "$1" | od -An -tx1; timeout 120 "$1"; echo "exit code: $?"' sh "$bin" || true
    echo "::endgroup::"
}

# run.py only records that a test runner crashed; what it printed is in the
# runner's own log next to its script, which is not under artifacts/log. Show
# the end of each crashed runner's log and keep all of them with the results.
report_runners()
{
    local logs="${RUNTIME_DIR}/artifacts/log" crashed script log
    local tests="${RUNTIME_DIR}/artifacts/tests/coreclr/linux.riscv64.Checked"

    sudo_if_needed mkdir -p "${logs}/runners"
    ( cd "${tests}" && find . -name '*.log' -print0 |
        sudo_if_needed xargs -0 -r cp --parents -t "${logs}/runners" ) || true

    for crashed in "${logs}"/*.testRun.xml.crashed ; do
        [ -f "$crashed" ] || continue
        script="$(sed -n 's/^Script=//p' "$crashed")"
        log="${script%.sh}.log"
        echo "::group::crashed runner ${script#${tests}/}"
        if [ -f "$log" ] ; then
            tail -n 60 "$log"
        else
            echo "(no log at ${log})"
        fi
        echo "::endgroup::"
    done
}

# The build runs as root in the container, so the test tree on the host belongs
# to root; use sudo for writing there when not already root.
sudo_if_needed()
{
    if [ "$(id -u)" = "0" ] || ! command -v sudo > /dev/null ; then
        "$@"
    else
        sudo "$@"
    fi
}

step="${1:-}"
shift || true
case "$step" in
    source) [ $# -eq 3 ] || die "usage: $0 source <vmr fork> <vmr branch> <profile>" ; step_source "$@" ;;
    rootfs) step_rootfs ;;
    build)  [ $# -eq 1 ] || die "usage: $0 build <coreclr|nativeaot>" ; step_build "$1" ;;
    run)    [ $# -eq 1 ] || die "usage: $0 run <coreclr|nativeaot>" ; step_run "$1" ;;
    *)      die "usage: $0 source|rootfs|build|run ..." ;;
esac
