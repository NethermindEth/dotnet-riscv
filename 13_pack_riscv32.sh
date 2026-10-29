#!/bin/bash
# Packs the riscv32 target of bflat from the build of 12_build_runtime_riscv32.sh,
# as 11_pack_x64.sh packs the linux-x64 target:
#
#   bflat-compiler-native-riscv32-linux-glibc-x64.zip  -> the bflat directory:
#       libclrjit_unix_riscv32_x64.so, the JIT that the ILCompiler of the
#       bflat.compiler package loads for riscv32
#   bflat-libs-linux-musl-riscv32.zip                  -> the riscv32 lib
#       directory: the NativeAOT runtime, CoreLib, libSystem.Native and the
#       framework libraries
#   libs-linux-musl-riscv32.zip                        -> the same directory:
#       the files of the sysroot that the link needs (crt objects, libc,
#       libatomic, the compiler-rt builtins)
#   crossrootfs-musl-riscv32.tar.xz                    -> the whole rv32im
#       sysroot, headers included, for the C modules that bflat builds
#
# A file that bflat links and that is not in the build is an error here, so
# that a release cannot miss it. So is an object that the guest cannot run:
# one that is not ilp32 or claims the C extension (check_ilp32.sh), or one
# that carries a compressed, atomic or fence instruction (tools/isa_scan.py).
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$0")" ; pwd -P)"

RUNTIME_DIR="${TOP_DIR}/runtime"
ART="${RUNTIME_DIR}/artifacts"
SYSROOT="${TOP_DIR}/crossrootfs/riscv32"
OUT="${TOP_DIR}/output/riscv32"

die()
{
    echo "13_pack_riscv32.sh: $*" >&2
    exit 1
}

# Fails with the names of the files of $@ that are not in directory $1.
require()
{
    local dir="$1" f missing=()
    shift
    for f in "$@" ; do
        [ -e "${dir}/${f}" ] || missing+=("$f")
    done
    [ ${#missing[@]} -eq 0 ] || die "${dir} has no ${missing[*]}"
}

# The cross-build image for x64 of the runtime sources: the linux_x64
# container of their pipelines, which has the LLVM tools.
x64_image()
{
    awk '/^ *linux_x64:$/ { f = 1; next } f && $1 == "image:" { print $2; exit }' \
        "${RUNTIME_DIR}/eng/pipelines/common/templates/pipeline-with-resources.yml" 2>/dev/null
}

IMAGE="${IMAGE_X64:-$(x64_image)}"
[ -n "${IMAGE}" ] || die "the pipelines of ${RUNTIME_DIR} name no linux_x64 image: set IMAGE_X64"

rm -rf "${OUT}"
mkdir -p "${OUT}/jit" "${OUT}/libs" "${OUT}/sysroot"

# The JIT.
host="${ART}/bin/coreclr/linux.x64.Release"
require "${host}" libclrjit_unix_riscv32_x64.so
cp "${host}/libclrjit_unix_riscv32_x64.so" "${OUT}/jit/"

# The runtime. The framework first, then the aotsdk: the NativeAOT CoreLib
# and the private libraries replace a file with the same name. The framework
# is the x64 build of libs.sfx: outside CoreLib, its IL does not depend on the
# architecture.
sfx="$(ls -d "${ART}"/bin/microsoft.netcore.app.runtime.linux-x64/Release/runtimes/linux-x64/lib/net[0-9]*/ 2>/dev/null | sort -V | tail -n1)"
[ -n "${sfx}" ] || die "no framework libraries under ${ART}/bin/microsoft.netcore.app.runtime.linux-x64"
native="$(ls -d "${ART}"/bin/native/net[0-9]*-linux-Release-riscv32/ 2>/dev/null | sort -V | tail -n1)"
[ -n "${native}" ] || die "no riscv32 native libraries under ${ART}/bin/native"
aotsdk="${ART}/bin/coreclr/linux.riscv32.Release/aotsdk"
[ -d "${aotsdk}" ] || die "no NativeAOT runtime at ${aotsdk}"

cp "${sfx}"*.dll "${OUT}/libs/"
# riscv32 builds the native libraries static only (STATIC_LIBS_ONLY), which
# the build installs under lib/.
compgen -G "${native}lib/*.a" > /dev/null || die "no riscv32 native libraries under ${native}lib"
cp "${native}"lib/*.a "${OUT}/libs/"
cp "${aotsdk}"/*.a "${aotsdk}"/*.o "${aotsdk}"/*.dll "${OUT}/libs/"
require "${OUT}/libs" \
    libbootstrapper.o libbootstrapperdll.o \
    libRuntime.WorkstationGC.a libaotminipal.a libeventpipe-disabled.a \
    libstandalonegc-disabled.a libstdc++compat.a \
    libSystem.Native.a libSystem.IO.Compression.Native.a \
    System.Private.CoreLib.dll System.Private.TypeLoader.dll \
    System.Private.Reflection.Execution.dll System.Private.StackTraceMetadata.dll \
    System.Runtime.dll System.Console.dll
echo "riscv32 native libraries: $(cd "${native}lib" && ls *.a | tr '\n' ' ')"

# The sysroot files that the link takes: musl's crt objects and libraries,
# the soft libatomic and the compiler-rt builtins.
cp "${SYSROOT}"/usr/lib/*.a "${SYSROOT}"/usr/lib/*.o "${OUT}/sysroot/"
require "${OUT}/sysroot" crt1.o crti.o crtn.o libc.a libm.a libatomic.a libclang_rt.builtins-riscv32.a

# In the build container, which has the LLVM tools: the debug information
# goes, as for the riscv64 libraries, and then the gates.
docker run --platform linux/amd64 --rm -v "${TOP_DIR}:${TOP_DIR}" -w "${OUT}" "$IMAGE" bash -euc '
    llvm-strip --strip-debug libs/*.a libs/*.o sysroot/*.a sysroot/*.o
    "$0/check_ilp32.sh" libs sysroot
    OBJDUMP=llvm-objdump ISA_SCAN_FENCE=1 python3 "$0/tools/isa_scan.py" libs/*.a libs/*.o sysroot/*.a sysroot/*.o
    chmod -R a+rwX .' "${TOP_DIR}"

pack()
{
    local dir="$1" zip="$2"
    rm -f "${OUT}/${zip}"
    ( cd "${dir}" && zip -qr "${OUT}/${zip}" . )
    echo "packed ${OUT}/${zip}: $(ls "${dir}" | wc -l) files"
}

pack "${OUT}/jit" bflat-compiler-native-riscv32-linux-glibc-x64.zip
pack "${OUT}/libs" bflat-libs-linux-musl-riscv32.zip
pack "${OUT}/sysroot" libs-linux-musl-riscv32.zip
tar -C "${SYSROOT}" -cJf "${OUT}/crossrootfs-musl-riscv32.tar.xz" .
echo "packed ${OUT}/crossrootfs-musl-riscv32.tar.xz"
