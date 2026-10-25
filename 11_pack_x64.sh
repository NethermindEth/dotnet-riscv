#!/bin/bash
# Packs the linux-x64 target of bflat from the build of 10_build_runtime_x64.sh,
# in the layout that bflat.csproj unpacks:
#
#   bflat-compiler-native-x64-linux-glibc-x64.zip  -> the bflat directory:
#       libclrjit_unix_x64_x64.so, the JIT that ILCompiler loads for x64
#   bflat-libs-linux-glibc-x64.zip                 -> lib/linux/x64/glibc:
#       the NativeAOT runtime, CoreLib and the framework libraries
#   libs-linux-glibc-x64.zip                       -> lib/linux/x64/glibc:
#       the glibc and gcc files of the rootfs that the link needs (crt
#       objects, libc, libm, libgcc, ...)
#
# A file that bflat links and that is not in the build is an error here, so
# that a release cannot miss it.
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

RUNTIME_DIR="${TOP_DIR}/runtime"
ART="${RUNTIME_DIR}/artifacts"
OUT="${TOP_DIR}/output/x64"

die()
{
    echo "11_pack_x64.sh: $*" >&2
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
# container of their pipelines. A .NET 10 and a .NET 11 build each get the
# image of their own branch.
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
coreclr="${ART}/bin/coreclr/linux.x64.Release"
require "${coreclr}" libclrjit_unix_x64_x64.so
cp "${coreclr}/libclrjit_unix_x64_x64.so" "${OUT}/jit/"

# The runtime. The framework first, then the aotsdk: the NativeAOT CoreLib
# and the private libraries replace a file with the same name.
sfx="$(ls -d "${ART}"/bin/microsoft.netcore.app.runtime.linux-x64/Release/runtimes/linux-x64/lib/net[0-9]*/ 2>/dev/null | sort -V | tail -n1)"
[ -n "${sfx}" ] || die "no framework libraries under ${ART}/bin/microsoft.netcore.app.runtime.linux-x64"
native="$(ls -d "${ART}"/bin/native/net[0-9]*-linux-Release-x64/ 2>/dev/null | sort -V | tail -n1)"
[ -n "${native}" ] || die "no native libraries under ${ART}/bin/native"
aotsdk="${coreclr}/aotsdk"
[ -d "${aotsdk}" ] || die "no NativeAOT runtime at ${aotsdk}"

cp "${sfx}"*.dll "${OUT}/libs/"
cp "${native}"*.a "${OUT}/libs/"
cp "${aotsdk}"/*.a "${aotsdk}"/*.o "${aotsdk}"/*.dll "${OUT}/libs/"
require "${OUT}/libs" \
    libbootstrapper.o libbootstrapperdll.o \
    libRuntime.WorkstationGC.a libRuntime.VxsortEnabled.a libaotminipal.a libeventpipe-disabled.a \
    libstandalonegc-disabled.a libstdc++compat.a \
    libSystem.Native.a libSystem.Globalization.Native.a \
    libSystem.IO.Compression.Native.a libSystem.Security.Cryptography.Native.OpenSsl.a \
    System.Private.CoreLib.dll System.Private.TypeLoader.dll \
    System.Private.Reflection.Execution.dll System.Private.StackTraceMetadata.dll \
    System.Runtime.dll System.Console.dll
[ -e "${OUT}/libs/libz.a" ] || echo "11_pack_x64.sh: no libz.a: the link takes libz from the rootfs" >&2
strip --strip-debug "${OUT}"/libs/*.a "${OUT}"/libs/*.o

# The sysroot: the files of the rootfs that the link of bflat names, with
# the symbolic links resolved. The linker scripts (libc.so and the like)
# name their files with the absolute paths of the rootfs; they are written
# with the bare names, which ld.lld looks for next to the script.
docker run --platform linux/amd64 --rm \
    -v "${OUT}/sysroot:/out" \
    "$IMAGE" \
    sh -euc '
        r=/crossrootfs/x64
        gcc_dir=$(ls -d $r/usr/lib/gcc/x86_64-linux-gnu/* | sort -V | tail -n1)
        for f in \
            $r/usr/lib/x86_64-linux-gnu/Scrt1.o $r/usr/lib/x86_64-linux-gnu/crt1.o \
            $r/usr/lib/x86_64-linux-gnu/crti.o $r/usr/lib/x86_64-linux-gnu/crtn.o \
            $r/usr/lib/x86_64-linux-gnu/lib*_nonshared.a \
            $r/usr/lib/x86_64-linux-gnu/libc.so $r/usr/lib/x86_64-linux-gnu/libm.so \
            $r/usr/lib/x86_64-linux-gnu/libpthread.so $r/usr/lib/x86_64-linux-gnu/libdl.so \
            $r/usr/lib/x86_64-linux-gnu/librt.so $r/usr/lib/x86_64-linux-gnu/libatomic.so* \
            $r/usr/lib/x86_64-linux-gnu/libz.so \
            $r/lib/x86_64-linux-gnu/libc.so.6 $r/lib/x86_64-linux-gnu/libm.so.6 \
            $r/lib/x86_64-linux-gnu/libmvec.so.1 $r/lib/x86_64-linux-gnu/libpthread.so.0 \
            $r/lib/x86_64-linux-gnu/libdl.so.2 $r/lib/x86_64-linux-gnu/librt.so.1 \
            $r/lib/x86_64-linux-gnu/libgcc_s.so.1 $r/lib/x86_64-linux-gnu/libz.so.1 \
            $r/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 \
            $gcc_dir/crtbeginS.o $gcc_dir/crtendS.o $gcc_dir/libgcc.a $gcc_dir/libgcc_eh.a \
            $gcc_dir/libgcc_s.so $gcc_dir/libatomic.a $gcc_dir/libatomic.so ; do
            [ -e "$f" ] && cp -L "$f" /out/ || true
        done
        chmod -R a+rwX /out'

sysroot="${OUT}/sysroot"
for f in "${sysroot}"/* ; do
    if head -c 512 "$f" | grep -q 'GNU ld script' ; then
        sed -i -E 's#(^|[ (])/[^ ()]*/#\1#g' "$f"
        echo "linker script $(basename "$f"): $(grep -E 'GROUP|INPUT' "$f" | tr -s ' ')"
    fi
done
require "${sysroot}" Scrt1.o crti.o crtn.o crtbeginS.o crtendS.o \
    libc.so libc.so.6 libc_nonshared.a libm.so libdl.so libpthread.so librt.so \
    libgcc.a libgcc_s.so libgcc_s.so.1 ld-linux-x86-64.so.2
compgen -G "${sysroot}/libatomic.*" > /dev/null || die "the rootfs has no libatomic, which bflat links"
if ! compgen -G "${sysroot}/libz.*" > /dev/null && [ ! -e "${OUT}/libs/libz.a" ] ; then
    die "neither the runtime nor the rootfs has libz, which bflat links"
fi

pack()
{
    local dir="$1" zip="$2"
    rm -f "${OUT}/${zip}"
    ( cd "${dir}" && zip -qr "${OUT}/${zip}" . )
    echo "packed ${OUT}/${zip}: $(ls "${dir}" | wc -l) files"
}

pack "${OUT}/jit" bflat-compiler-native-x64-linux-glibc-x64.zip
pack "${OUT}/libs" bflat-libs-linux-glibc-x64.zip
pack "${OUT}/sysroot" libs-linux-glibc-x64.zip
