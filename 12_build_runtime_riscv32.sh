#!/bin/bash
# Builds the riscv32 (RV32IM ilp32) target of bflat from the dotnet/runtime
# checkout that "runtime_tests.sh source" makes with RISCV32=1 and the
# upstream-perf profile:
#
#   RISCV32=1 runtime_tests.sh source <vmr fork> <vmr branch> upstream-perf
#   12_build_runtime_riscv32.sh
#   13_pack_riscv32.sh
#
# Three steps, all in the x64 cross-build container of the checkout (the
# image of its pipelines, as 10_build_runtime_x64.sh uses), which has clang
# and the LLVM tools:
#
# 1. the rv32im sysroot: musl, the soft libatomic, the compiler-rt builtins
#    (build_*_rv32im.sh), the Linux UAPI headers
#    (install_linux_headers_rv32.sh) and the libc++ headers
#    (build_libcxx_headers_rv32.sh), in crossrootfs/riscv32;
# 2. the riscv32 NativeAOT runtime, its CoreLib and libSystem.Native,
#    cross-built against the sysroot. riscv32 is NativeAOT-only: CoreCLR
#    and the framework libraries are not built for it;
# 3. the x64-hosted compiler: ILCompiler with the RiscV32 target, its
#    jitinterface and the cross JITs, among them clrjit_unix_riscv32_x64
#    (a community JIT, hence clr.alljitscommunity). It is the longest step,
#    so it comes last.
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

RUNTIME_DIR="${TOP_DIR}/runtime"
SYSROOT="${TOP_DIR}/crossrootfs/riscv32"

# The cross-build image for x64 of the runtime sources: the linux_x64
# container of their pipelines.
x64_image()
{
    awk '/^ *linux_x64:$/ { f = 1; next } f && $1 == "image:" { print $2; exit }' \
        "${RUNTIME_DIR}/eng/pipelines/common/templates/pipeline-with-resources.yml" 2>/dev/null
}

[ -d "${RUNTIME_DIR}/src/coreclr" ] || { echo "${RUNTIME_DIR} has no runtime sources: run runtime_tests.sh source first" >&2; exit 1; }
grep -q '^#define TARGET_RISCV 1$' "${RUNTIME_DIR}/src/coreclr/jit/jit.h" \
    || { echo "${RUNTIME_DIR} is not patched for riscv32: run runtime_tests.sh source with RISCV32=1" >&2; exit 1; }
IMAGE="${IMAGE_X64:-$(x64_image)}"
[ -n "${IMAGE}" ] || { echo "the pipelines of ${RUNTIME_DIR} name no linux_x64 image: set IMAGE_X64" >&2; exit 1; }
echo "x64 build image: ${IMAGE}"

in_container()
{
    docker run --platform linux/amd64 --rm \
        -v "${TOP_DIR}:${TOP_DIR}" \
        -w "${RUNTIME_DIR}" \
        "$@"
}

echo "== rv32im sysroot"
rm -rf "${SYSROOT}"
in_container "$IMAGE" bash -euc '
    clang --version | head -n1
    missing=
    for t in clang clang++ llvm-ar llvm-ranlib llvm-nm llvm-objdump make cmake ninja curl git tar gzip python3 nproc ; do
        command -v "$t" > /dev/null || missing="$missing $t"
    done
    [ -z "$missing" ] || { echo "the build container has no$missing" >&2 ; exit 1 ; }
    "$0/build_musl_rv32im.sh" "$1"
    "$0/build_libatomic_rv32im.sh" "$1"
    "$0/build_builtins_rv32im.sh" "$1"
    "$0/install_linux_headers_rv32.sh" "$1"
    "$0/build_libcxx_headers_rv32.sh" "$1"' "${TOP_DIR}" "${SYSROOT}"

echo "== riscv32 NativeAOT runtime"
# The ISA and the ABI reach toolchain.cmake through the environment, as they do
# for the soft-float riscv64 build: cmake's own probes would otherwise be built
# for clang's default rv32 ABI (ilp32d) and fail to link against the sysroot.
in_container -e ROOTFS_DIR="${SYSROOT}" \
             -e CLR_CMAKE_RISCV64_MARCH=rv32im -e CLR_CMAKE_RISCV64_MABI=ilp32 \
             "$IMAGE" \
    ./build.sh -s clr.nativeaotruntime+clr.nativeaotlibs+libs.native \
               -c Release --cross --arch riscv32 --os linux \
               /p:RunAnalyzers=false

echo "== x64-hosted compiler"
in_container -e ROOTFS_DIR=/crossrootfs/x64 "$IMAGE" \
    ./build.sh -s clr.alljitscommunity+clr.aot \
               -c Release --cross --arch x64 --os linux \
               /p:RunAnalyzers=false
