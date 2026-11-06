#!/bin/bash
# Install the Linux UAPI headers (linux/, asm/, asm-generic/, ...) into a
# sysroot made by build_musl_rv32im.sh. The runtime includes some of them
# (linux/membarrier.h, ...); musl does not ship them.
#
# They come from Alpine's riscv64 linux-headers package, pinned by version and
# sha256. The RISC-V UAPI headers do not depend on XLEN (bitsperlong.h derives
# it from __SIZEOF_POINTER__), so the riscv64 package serves riscv32 as well.
set -euo pipefail

sysroot="${1:?usage: install_linux_headers_rv32.sh <sysroot-dir>}"

alpine="v3.22"
version="6.14.2-r0"
sha256="8ae41d83c149efb027ef3ef3a5a08f30572eb5d12466ee238cfd4ebc21267f24"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

apk="linux-headers-$version.apk"
curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/$alpine/main/riscv64/$apk" -o "$work/$apk"
actual="$(sha256sum "$work/$apk" 2>/dev/null || shasum -a 256 "$work/$apk")"
[ "${actual%% *}" = "$sha256" ] || { echo "$apk: sha256 ${actual%% *}, expected $sha256" >&2; exit 1; }

# An apk is gzip-compressed tar streams; the headers are under usr/include.
mkdir -p "$work/x"
tar xzf "$work/$apk" -C "$work/x" usr/include 2>/dev/null
[ -f "$work/x/usr/include/linux/membarrier.h" ] || { echo "$apk has no usr/include/linux" >&2; exit 1; }

mkdir -p "$sysroot/usr/include"
cp -R "$work/x/usr/include/." "$sysroot/usr/include/"
echo "Installed the Linux $version UAPI headers into $sysroot/usr/include"
