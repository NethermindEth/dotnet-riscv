#!/bin/bash
# Build the soft libatomic for the single-hart rv32im zkVM guest and install it
# into a sysroot made by build_musl_rv32im.sh. libatomic/libatomic_soft32.c is
# the clang/rv32 form of libatomic_soft.c: the full __atomic_* ABI as plain
# load/modify/store, which the ISA scan gate checks for C/A instructions.
#
# CC, AR and OBJDUMP override the LLVM tools (default: clang, llvm-ar,
# llvm-objdump).
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

sysroot="${1:?usage: build_libatomic_rv32im.sh <sysroot-dir>}"

cc="${CC:-clang}"
ar="${AR:-llvm-ar}"
# -fno-builtin: the generic __atomic_* names are compiler builtins; without this
# the compiler refuses to let us define them.
cflags="--target=riscv32-unknown-linux-musl -march=rv32im -mabi=ilp32 -mno-relax -O2 -ffreestanding -fno-builtin -fno-stack-protector -Wno-builtin-declaration-mismatch"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

"$cc" $cflags -c "$TOP_DIR/libatomic/libatomic_soft32.c" -o "$work/libatomic_soft.o"
"$ar" rcs "$work/libatomic.a" "$work/libatomic_soft.o"

ISA_SCAN_FENCE=1 OBJDUMP="${OBJDUMP:-llvm-objdump}" python3 "$TOP_DIR/tools/isa_scan.py" "$work/libatomic.a"

mkdir -p "$sysroot/usr/lib"
cp "$work/libatomic.a" "$sysroot/usr/lib/"
echo "Installed rv32im soft libatomic.a into $sysroot/usr/lib"
