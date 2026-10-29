#!/bin/bash
# Build compiler-rt's builtins (64-bit integer division/shift helpers, the
# soft-float library) for rv32im/ilp32 and install
# libclang_rt.builtins-riscv32.a into a sysroot made by build_musl_rv32im.sh.
#
# Clang targeting rv32 calls these for every 64-bit divide and every float
# operation, and no distribution ships them for riscv32. Only the portable C
# sources are compiled: they need no target assembly. The compiler-rt sources
# are taken at the tag of the clang that builds them, so the helper ABI matches.
#
# CC, AR, NM and OBJDUMP override the LLVM tools (default: clang, llvm-ar,
# llvm-nm, llvm-objdump).
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$0")" ; pwd -P)"

sysroot="${1:?usage: build_builtins_rv32im.sh <sysroot-dir> [llvm-tag]}"

cc="${CC:-clang}"
ar="${AR:-llvm-ar}"
tag="${2:-}"
if [ -z "$tag" ] ; then
    version="$("$cc" -dumpversion)"
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ; then
        echo "$cc -dumpversion gives '$version', not a full LLVM version: pass the llvm tag" >&2
        exit 1
    fi
    tag="llvmorg-$version"
fi

[ -f "$sysroot/usr/lib/libc.a" ] || { echo "$sysroot has no libc.a: run build_musl_rv32im.sh first" >&2; exit 1; }

cflags="--target=riscv32-unknown-linux-musl -march=rv32im -mabi=ilp32 -mno-relax -O2 -fno-stack-protector"
cflags="$cflags --sysroot=$sysroot -ffreestanding -fno-builtin -fvisibility=hidden -DCOMPILER_RT_HAS_FLOAT16=0"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Fetching compiler-rt builtins ($tag)"
git -C "$work" clone -q --depth 1 --filter=blob:none --sparse -b "$tag" \
    https://github.com/llvm/llvm-project.git llvm
git -C "$work/llvm" sparse-checkout set compiler-rt/lib/builtins
src="$work/llvm/compiler-rt/lib/builtins"

mkdir -p "$work/obj"
for c in "$src"/*.c; do
    name="$(basename "$c" .c)"
    case "$name" in
        # Need target or OS support a bare rv32im guest does not have.
        atomic|clear_cache|enable_execute_stack|emutls|eprintf|gcc_personality_v0|os_version_check|trampoline_setup|apple_versioning)
            continue ;;
        # crt objects, not builtins.
        crtbegin|crtend)
            continue ;;
        # The C11 atomic flag and fence functions: clang inlines them, and the fence they
        # carry has no place on the single-hart guest.
        atomic_flag_*|atomic_thread_fence|atomic_signal_fence)
            continue ;;
        # x87 80-bit long double (xf) helpers: rv32 has no such type.
        *xf*|divxc3|mulxc3)
            continue ;;
    esac
    "$cc" $cflags -I"$src" -c "$c" -o "$work/obj/$name.o"
done

# The helpers the rv32 code depends on; a missing one only shows up later, at
# the link of the runtime or of the guest.
"$ar" rcs "$work/libclang_rt.builtins-riscv32.a" "$work"/obj/*.o
defined="$("${NM:-llvm-nm}" -g --defined-only "$work/libclang_rt.builtins-riscv32.a" | awk 'NF == 3 { print $3 }')"
for sym in __divdi3 __udivdi3 __moddi3 __umoddi3 __ashldi3 __lshrdi3 __ashrdi3 \
           __adddf3 __subdf3 __muldf3 __divdf3 __addsf3 __mulsf3 __divsf3 \
           __fixdfdi __floatdidf __extendsfdf2 __truncdfsf2 ; do
    grep -qx -- "$sym" <<<"$defined" || { echo "builtins archive has no $sym" >&2; exit 1; }
done

ISA_SCAN_FENCE=1 OBJDUMP="${OBJDUMP:-llvm-objdump}" python3 "$TOP_DIR/tools/isa_scan.py" \
    "$work/libclang_rt.builtins-riscv32.a"

mkdir -p "$sysroot/usr/lib"
cp "$work/libclang_rt.builtins-riscv32.a" "$sysroot/usr/lib/"
echo "Installed $(ls "$work/obj" | wc -l | tr -d ' ') builtins objects into $sysroot/usr/lib/libclang_rt.builtins-riscv32.a"
