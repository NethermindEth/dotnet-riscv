#!/bin/bash
# Build upstream musl for the rv32im zkVM target (ilp32, no C, no A, no F/D) and
# install it as a static sysroot: headers, libc.a and the crt objects. The
# riscv32 runtime build takes this sysroot as its CROSS_ROOTFS.
#
# rv32 has no Alpine port to stay in lockstep with, so this takes a pinned
# upstream release. Like build_musl_rv64im.sh it drops the lr/sc reservation
# loop from atomic_arch.h (the guest is single-hart), and the ISA scan gate
# enforces that no C/A instruction is left.
#
# There is no riscv32 gcc, so the build uses clang. CC, AR, RANLIB and OBJDUMP
# override the LLVM tools (default: clang, llvm-ar, llvm-ranlib, llvm-objdump).
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$0")" ; pwd -P)"

sysroot="${1:?usage: build_musl_rv32im.sh <sysroot-dir>}"

version="1.2.5"
sha256="a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4"

cc="${CC:-clang}"
ar="${AR:-llvm-ar}"
ranlib="${RANLIB:-llvm-ranlib}"
cflags="--target=riscv32-unknown-linux-musl -march=rv32im -mabi=ilp32 -mno-relax -O2 -fno-stack-protector"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsSL "https://musl.libc.org/releases/musl-$version.tar.gz" -o "$work/musl.tar.gz"
actual="$(sha256sum "$work/musl.tar.gz" 2>/dev/null || shasum -a 256 "$work/musl.tar.gz")"
[ "${actual%% *}" = "$sha256" ] || { echo "musl-$version.tar.gz: sha256 ${actual%% *}, expected $sha256" >&2; exit 1; }
tar xzf "$work/musl.tar.gz" -C "$work"
src="$work/musl-$version"

patch -d "$src" -p1 --silent < "$TOP_DIR/musl/atomic_arch_rv32im.patch"

pushd "$src" >/dev/null
    # LIBCC="": the sysroot has no compiler runtime yet (build_builtins_rv32im.sh
    # adds it), and libc.a is static, so nothing links against it here.
    CC="$cc" CFLAGS="$cflags" LIBCC="" \
        ./configure --target=riscv32 --disable-shared --prefix="$work/out" >/dev/null
    make AR="$ar" RANLIB="$ranlib" -j"$(nproc)" >/dev/null
    make AR="$ar" RANLIB="$ranlib" install >/dev/null
popd >/dev/null

ISA_SCAN_FENCE=1 OBJDUMP="${OBJDUMP:-llvm-objdump}" python3 "$TOP_DIR/tools/isa_scan.py" \
    "$work/out/lib/libc.a" "$work/out/lib/crt1.o" \
    "$work/out/lib/crti.o" "$work/out/lib/crtn.o"

mkdir -p "$sysroot/usr"
cp -R "$work/out/include" "$work/out/lib" "$sysroot/usr/"

# The runtime's CMake recognises a musl sysroot by "musl" in usr/bin/ldd; a
# static-only sysroot has no loader, so leave a marker there.
mkdir -p "$sysroot/usr/bin"
echo "musl libc (static rv32im sysroot marker)" > "$sysroot/usr/bin/ldd"

echo "Installed rv32im musl $version into $sysroot"
