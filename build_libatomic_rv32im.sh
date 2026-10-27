#!/bin/bash
# Build the soft libatomic (libatomic/libatomic_soft32.c, the clang/rv32 form of libatomic_soft.c) for
# the rv32im zkVM guest and install it into a sysroot. The guest is single-hart, so the
# __atomic_* ABI is plain load/modify/store. Uses clang (no riscv32 gcc is assumed).
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$0")" ; pwd -P)"

sysroot="${1:?usage: build_libatomic_rv32im.sh <sysroot-dir>}"

# -fno-builtin: the generic __atomic_* names are compiler builtins; without this
# the compiler refuses to let us define them.
cflags="--target=riscv32-unknown-linux-musl -march=rv32im -mabi=ilp32 -mno-relax -O2 -ffreestanding -fno-builtin -fno-stack-protector -Wno-builtin-declaration-mismatch"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

clang $cflags -c "$TOP_DIR/libatomic/libatomic_soft32.c" -o "$work/libatomic_soft.o"
llvm-ar rcs "$work/libatomic.a" "$work/libatomic_soft.o"

mkdir -p "$sysroot/usr/lib"
cp "$work/libatomic.a" "$sysroot/usr/lib/"
echo "Installed rv32im soft libatomic.a into $sysroot/usr/lib"
