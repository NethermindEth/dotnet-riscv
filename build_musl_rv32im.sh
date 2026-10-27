#!/bin/bash
# Build upstream musl for the rv32im zkVM target (ilp32, no C, no A, no F/D) and
# install it as a minimal sysroot: headers, libc.a and the crt objects.
#
# rv32 has no Alpine port to stay in lockstep with, so this takes the upstream
# release directly. Like build_musl_rv64im.sh it replaces the lr/sc reservation
# loops in atomic_arch.h with a plain read-compare-write: the guest is single-hart.
# It compiles with clang (no riscv32 gcc is assumed), so run it where clang,
# llvm-ar and llvm-ranlib are on PATH, e.g. the dotnet-buildtools cross image.
set -euo pipefail

sysroot="${1:?usage: build_musl_rv32im.sh <sysroot-dir> [musl-version]}"
version="${2:-1.2.5}"

target="riscv32-unknown-linux-musl"
cflags="--target=$target -march=rv32im -mabi=ilp32 -mno-relax -O2 -fno-stack-protector"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -sSL "https://musl.libc.org/releases/musl-$version.tar.gz" -o "$work/musl.tar.gz"
tar xzf "$work/musl.tar.gz" -C "$work"
src="$work/musl-$version"

python3 - "$src/arch/riscv32/atomic_arch.h" <<'PY'
import re, sys
path = sys.argv[1]
s = open(path).read()
cas = (
    "#define a_cas a_cas\n"
    "static inline int a_cas(volatile int *p, int t, int s)\n"
    "{\n"
    "\t// Single-hart zkVM target (no A extension): a plain read-compare-write cannot race\n"
    "\tint old = *p;\n"
    "\tif (old == t) *p = s;\n"
    "\treturn old;\n"
    "}\n")
cas_p = (
    "#define a_cas_p a_cas_p\n"
    "static inline void *a_cas_p(volatile void *p, void *t, void *s)\n"
    "{\n"
    "\tvoid *old = *(void *volatile *)p;\n"
    "\tif (old == t) *(void *volatile *)p = s;\n"
    "\treturn old;\n"
    "}\n")
s, n1 = re.subn(r"#define a_cas a_cas\n.*?\n}\n", lambda m: cas, s, count=1, flags=re.S)
s, n2 = re.subn(r"#define a_cas_p a_cas_p\n.*?\n}\n", lambda m: cas_p, s, count=1, flags=re.S)
# riscv32 has no a_cas_p of its own: a pointer is an int there.
if n1 != 1 or n2 > 1 or "lr." in s or "sc." in s:
    sys.exit(f"{path}: unexpected atomic_arch.h layout ({n1}, {n2})")
open(path, "w").write(s)
PY

pushd "$src" >/dev/null
    CC=clang CFLAGS="$cflags" LIBCC="" \
        ./configure --target=riscv32 --disable-shared --prefix="$sysroot/usr" \
                    --syslibdir="$sysroot/lib" >/dev/null
    make AR=llvm-ar RANLIB=llvm-ranlib -j"$(nproc)" >/dev/null
    make AR=llvm-ar RANLIB=llvm-ranlib install >/dev/null
popd >/dev/null

# The runtime's CMake recognises a musl sysroot by "musl" in usr/bin/ldd; a static-only
# sysroot has no loader, so leave a marker there.
mkdir -p "$sysroot/usr/bin"
echo "musl libc (static rv32im sysroot marker)" > "$sysroot/usr/bin/ldd"

echo "Installed rv32im musl $version into $sysroot"
