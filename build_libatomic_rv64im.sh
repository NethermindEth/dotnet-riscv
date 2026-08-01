#!/bin/bash
# Build a soft libatomic for the strict rv64im zkVM guest and drop it into a
# rootfs lib directory, replacing the stock rv64gc GCC libatomic.
#
# The guest is single-hart and decodes only base rv64im, so the real libatomic
# (lr/sc plus a pthread lock table for non-lock-free sizes) is both illegal and
# unnecessary. libatomic/libatomic_soft.c implements the full __atomic_* ABI as
# plain load/modify/store; compiled -march=rv64im it carries no C/A instruction,
# which the ISA scan gate enforces.
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

target_libdir="${1:?usage: build_libatomic_rv64im.sh <target-usr-lib-dir>}"

cross="${CROSS_COMPILE:-riscv64-linux-gnu-}"
# -fno-builtin: the generic __atomic_* names are compiler builtins; without this
# the compiler refuses to let us define them.
cflags="-march=rv64im -mabi=lp64 -mno-relax -O2 -ffreestanding -fno-builtin -fno-stack-protector"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

"${cross}gcc" $cflags -c "$TOP_DIR/libatomic/libatomic_soft.c" -o "$work/libatomic_soft.o"
"${cross}ar" rcs "$work/libatomic.a" "$work/libatomic_soft.o"

OBJDUMP="${cross}objdump" python3 "$TOP_DIR/tools/isa_scan.py" "$work/libatomic.a"

mkdir -p "$target_libdir"
cp "$work/libatomic.a" "$target_libdir/"
echo "Installed rv64im soft libatomic.a into $target_libdir"
