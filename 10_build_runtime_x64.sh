#!/bin/bash
# Builds the linux-x64 target of bflat: the x64 JIT and the NativeAOT
# runtime and libraries, from the dotnet/runtime checkout that
# "runtime_tests.sh source" makes (the commit that the VMR pins, with the
# fixups of the profile and the JIT/EE GUID of bump_jitee_guid.sh). These
# sources are the same as those of the bflat.compiler package of the SDK
# build, so the JIT and CoreLib agree with its ILCompiler.
#
#   runtime_tests.sh source <vmr fork> <vmr branch> <profile>
#   10_build_runtime_x64.sh
#   11_pack_x64.sh
#
# The build runs in the cross-build container of dotnet/runtime for x64
# (the image that the pipelines of the checkout name), against its glibc
# rootfs, as the official linux-x64 build does. The
# rootfs is the oldest glibc that the runtime supports, so the binaries
# that bflat makes run on the same Linux versions as .NET itself.
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

RUNTIME_DIR="${TOP_DIR}/runtime"

# The cross-build image for x64 of the runtime sources: the linux_x64
# container of their pipelines. A .NET 10 and a .NET 11 build each get the
# image of their own branch.
x64_image()
{
    awk '/^ *linux_x64:$/ { f = 1; next } f && $1 == "image:" { print $2; exit }' \
        "${RUNTIME_DIR}/eng/pipelines/common/templates/pipeline-with-resources.yml" 2>/dev/null
}

[ -d "${RUNTIME_DIR}/src/coreclr" ] || { echo "${RUNTIME_DIR} has no runtime sources: run runtime_tests.sh source first" >&2; exit 1; }
IMAGE="${IMAGE_X64:-$(x64_image)}"
[ -n "${IMAGE}" ] || { echo "the pipelines of ${RUNTIME_DIR} name no linux_x64 image: set IMAGE_X64" >&2; exit 1; }
echo "x64 build image: ${IMAGE}"

# clr.alljits: the JITs for every target, among them clrjit_unix_x64_x64,
# which ILCompiler loads for a linux-x64 target. clr.aot: the NativeAOT
# runtime (aotsdk) and its CoreLib. libs.native and libs.sfx: the native
# and the managed framework libraries.
docker run --platform linux/amd64 --rm \
    -v "${TOP_DIR}:${TOP_DIR}" \
    -w "${RUNTIME_DIR}" \
    -e ROOTFS_DIR=/crossrootfs/x64 \
    "$IMAGE" \
    ./build.sh -s clr.alljits+clr.aot+libs.native+libs.sfx \
               -c Release --cross --arch x64 --os linux \
               /p:RunAnalyzers=false
