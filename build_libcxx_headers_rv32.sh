#!/bin/bash
# Install the libc++ headers, configured for rv32im/ilp32 musl, into a sysroot
# made by build_musl_rv32im.sh, at usr/include/c++/v1.
#
# The runtime's C++ needs the standard headers (<new>, <type_traits>, ...) and
# nothing of the C++ library itself: NativeAOT brings its own operator new and
# the like (libstdc++compat). No distribution has a C++ library for riscv32,
# so the headers are generated from libc++ at the tag of the clang that builds
# the runtime; toolchain.cmake points the riscv32 C++ compiles at them.
#
# CC and CXX override the compilers (default: clang, clang++); cmake and ninja
# must be on PATH.
set -euo pipefail

sysroot="${1:?usage: build_libcxx_headers_rv32.sh <sysroot-dir> [llvm-tag]}"

cc="${CC:-clang}"
cxx="${CXX:-clang++}"
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

flags="--target=riscv32-unknown-linux-musl -march=rv32im -mabi=ilp32 -mno-relax --sysroot=$sysroot"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Fetching libc++ ($tag)"
git -c advice.detachedHead=false -C "$work" clone -q --depth 1 --filter=blob:none --sparse -b "$tag" \
    https://github.com/llvm/llvm-project.git llvm
git -C "$work/llvm" sparse-checkout set libcxx libcxxabi runtimes cmake llvm/cmake llvm/utils/llvm-lit

# Only the headers are installed, so cmake's probes compile without linking
# (STATIC_LIBRARY), and the settings they would detect are given: musl, pthread,
# no C++ ABI library.
cmake -G Ninja -S "$work/llvm/runtimes" -B "$work/build" \
    -DLLVM_ENABLE_RUNTIMES=libcxx \
    -DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx" \
    -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags" \
    -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSROOT="$sysroot" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_INSTALL_PREFIX="$work/out" \
    -DLIBCXX_HAS_MUSL_LIBC=ON -DLIBCXX_HAS_PTHREAD_API=ON -DLIBCXX_CXX_ABI=none \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF > "$work/configure.log" || { cat "$work/configure.log" >&2; exit 1; }
ninja -C "$work/build" install-cxx-headers > /dev/null

headers="$work/out/include/c++/v1"
grep -q '^#define _LIBCPP_HAS_MUSL_LIBC 1$' "$headers/__config_site" \
    || { echo "the generated __config_site is not for musl" >&2; exit 1; }

# The headers must compile for the target the way the runtime uses them.
printf '#include <new>\n#include <type_traits>\n#include <atomic>\n#include <utility>\n#include <limits>\n' > "$work/check.cpp"
"$cxx" $flags -nostdinc++ -isystem "$headers" -std=c++17 -fno-exceptions -c "$work/check.cpp" -o "$work/check.o"

mkdir -p "$sysroot/usr/include/c++"
rm -rf "$sysroot/usr/include/c++/v1"
cp -R "$headers" "$sysroot/usr/include/c++/"
echo "Installed the libc++ $tag headers into $sysroot/usr/include/c++/v1"
