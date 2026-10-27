#!/bin/bash
# Build compiler-rt's builtins (64-bit integer division/shift helpers, the soft-float
# library) for rv32im/ilp32 and install libclang_rt.builtins-riscv32.a into a sysroot.
#
# Clang targeting rv32 calls these for every 64-bit divide and every float operation,
# and the dotnet-buildtools image ships x86_64 builtins only. Only the portable C
# sources are compiled: they need no target assembly. Run where clang and llvm-ar are
# on PATH; the LLVM tag should match that clang.
set -euo pipefail

sysroot="${1:?usage: build_builtins_rv32im.sh <sysroot-dir> [llvm-tag]}"
tag="${2:-llvmorg-20.1.8}"

cflags="--target=riscv32-unknown-linux-musl -march=rv32im -mabi=ilp32 -mno-relax -O2 -fno-stack-protector"
cflags="$cflags --sysroot=$sysroot -ffreestanding -fno-builtin -fvisibility=hidden -DCOMPILER_RT_HAS_FLOAT16=0"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git -C "$work" clone -q --depth 1 --filter=blob:none --sparse -b "$tag" \
    https://github.com/llvm/llvm-project.git llvm
git -C "$work/llvm" sparse-checkout set compiler-rt/lib/builtins
src="$work/llvm/compiler-rt/lib/builtins"

mkdir -p "$work/obj"
count=0
for c in "$src"/*.c; do
    name="$(basename "$c" .c)"
    case "$name" in
        # Need target or OS support a bare rv32im guest does not have.
        atomic|clear_cache|enable_execute_stack|emutls|eprintf|gcc_personality_v0|os_version_check|trampoline_setup|cpu_model)
            continue ;;
    esac
    if clang $cflags -I"$src" -c "$c" -o "$work/obj/$name.o" 2>/dev/null; then
        count=$((count + 1))
    fi
done

mkdir -p "$sysroot/usr/lib"
rm -f "$sysroot/usr/lib/libclang_rt.builtins-riscv32.a"
llvm-ar rcs "$sysroot/usr/lib/libclang_rt.builtins-riscv32.a" "$work"/obj/*.o
echo "Installed $count builtins objects into $sysroot/usr/lib/libclang_rt.builtins-riscv32.a"
