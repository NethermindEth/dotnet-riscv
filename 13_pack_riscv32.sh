#!/bin/bash
# Packs the riscv32 target of bflat from the build of 12_build_runtime_riscv32.sh:
#
#   bflat-compiler-riscv32-linux-glibc-x64.zip  -> bflat's LocalCompilerDir:
#       ILCompiler*.dll with the RiscV32 target, Microsoft.DiaSymReader.dll,
#       libjitinterface_x64.so and the libclrjit_unix_*_x64.so cross JITs
#   bflat-libs-linux-musl-riscv32.zip            -> the runtime half of bflat's
#       AirbenderLibsDir: the NativeAOT runtime and CoreLib for riscv32,
#       libSystem.Native.a, and libc.a, libatomic.a and the compiler-rt
#       builtins of the sysroot
#   crossrootfs-musl-riscv32.tar.xz              -> the whole rv32im sysroot
#       (headers included), for the RV32_SYSROOT of bflat's module build
#
# A file that bflat links and that is not in the build is an error here, so
# that a run cannot miss it.
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

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

rm -rf "${OUT}"
mkdir -p "${OUT}/compiler" "${OUT}/libs"

# The compiler. The managed assemblies come from their own x64 Release
# project outputs (never obj/); the native ones from the coreclr output.
host="${ART}/bin/coreclr/linux.x64.Release"
require "${host}" libjitinterface_x64.so libclrjit_unix_riscv32_x64.so libclrjit_unix_riscv64_x64.so
cp "${host}"/libjitinterface_x64.so "${host}"/libclrjit_unix_*_x64.so "${OUT}/compiler/"
while IFS= read -r dll ; do
    [ -e "${OUT}/compiler/$(basename "${dll}")" ] || cp "${dll}" "${OUT}/compiler/"
done < <(find "${ART}/bin" -type f \( -name 'ILCompiler*.dll' -o -name 'Microsoft.DiaSymReader.dll' \) \
             -path '*/x64/Release/*' ! -path '*/obj/*' ! -path '*Tests*' | sort)
require "${OUT}/compiler" \
    ILCompiler.Compiler.dll ILCompiler.DependencyAnalysisFramework.dll ILCompiler.MetadataTransform.dll \
    ILCompiler.RyuJit.dll ILCompiler.TypeSystem.dll Microsoft.DiaSymReader.dll
grep -q 'RiscV32' "${OUT}/compiler/ILCompiler.TypeSystem.dll" || die "ILCompiler.TypeSystem.dll has no RiscV32 target"

# The runtime.
target="${ART}/bin/coreclr/linux.riscv32.Release"
aotsdk="${target}/aotsdk"
[ -d "${aotsdk}" ] || die "no NativeAOT runtime at ${aotsdk}"
cp "${aotsdk}"/*.a "${aotsdk}"/*.o "${aotsdk}"/*.dll "${OUT}/libs/"
native="$(find "${ART}/bin/native" "${ART}/obj/coreclr/linux.riscv32.Release" -name libSystem.Native.a -path '*riscv32*' 2>/dev/null | head -n1)"
[ -n "${native}" ] || die "no riscv32 libSystem.Native.a under ${ART}"
cp "${native}" "${OUT}/libs/"
cp "${SYSROOT}/usr/lib/libc.a" "${SYSROOT}/usr/lib/libatomic.a" \
   "${SYSROOT}/usr/lib/libclang_rt.builtins-riscv32.a" "${OUT}/libs/"
require "${OUT}/libs" \
    libbootstrapper.o libRuntime.WorkstationGC.a libeventpipe-disabled.a libaotminipal.a \
    libstandalonegc-disabled.a libstdc++compat.a libSystem.Native.a \
    libc.a libatomic.a libclang_rt.builtins-riscv32.a \
    System.Private.CoreLib.dll System.Private.TypeLoader.dll

# The guest decodes RV32IM only: no compressed or atomic instruction may be in
# what it links. Fences are reported, not refused: the runtime C++ may still
# carry some. The scan runs in the build container, which has llvm-objdump.
x64_image()
{
    awk '/^ *linux_x64:$/ { f = 1; next } f && $1 == "image:" { print $2; exit }' \
        "${RUNTIME_DIR}/eng/pipelines/common/templates/pipeline-with-resources.yml" 2>/dev/null
}
IMAGE="${IMAGE_X64:-$(x64_image)}"
[ -n "${IMAGE}" ] || die "the pipelines of ${RUNTIME_DIR} name no linux_x64 image: set IMAGE_X64"
docker run --platform linux/amd64 --rm -v "${TOP_DIR}:${TOP_DIR}" -w "${OUT}/libs" "$IMAGE" bash -euc '
    OBJDUMP=llvm-objdump python3 "$0/tools/isa_scan.py" *.a *.o
    ISA_SCAN_FENCE=1 OBJDUMP=llvm-objdump python3 "$0/tools/isa_scan.py" *.a *.o \
        || echo "13_pack_riscv32.sh: the riscv32 libraries above carry fence instructions" >&2' "${TOP_DIR}"

pack()
{
    local dir="$1" zip="$2"
    rm -f "${OUT}/${zip}"
    ( cd "${dir}" && zip -qr "${OUT}/${zip}" . )
    echo "packed ${OUT}/${zip}: $(ls "${dir}" | wc -l) files"
}

pack "${OUT}/compiler" bflat-compiler-riscv32-linux-glibc-x64.zip
pack "${OUT}/libs" bflat-libs-linux-musl-riscv32.zip
tar -C "${SYSROOT}" -cJf "${OUT}/crossrootfs-musl-riscv32.tar.xz" .
echo "packed ${OUT}/crossrootfs-musl-riscv32.tar.xz"
