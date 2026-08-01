#!/bin/bash
# Rebuild Alpine's musl for the strict rv64im zkVM target (no C, no A, no F/D)
# and drop the result into a rootfs lib directory, replacing the stock rv64gc
# musl that build-rootfs.sh installs from the Alpine package feed.
#
# We reproduce the Alpine musl aport exactly (same 1.2.x tarball + the same
# ordered patch set, sparse-checked-out from aports so version/security fixes
# stay in lockstep with the rootfs) and add just one of our own patches:
# arch/riscv64/atomic_arch.h loses its lr/sc reservation loop (the guest is
# single-hart, so a plain read-compare-write is race-free). Compiling the whole
# thing -march=rv64im then yields a libc with zero C/A/F-D instructions, which
# the ISA scan gate enforces.
set -euo pipefail

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

# Where to install the rebuilt libc.a + crt objects (an Alpine musl rootfs lib
# dir, e.g. .../riscv64-musl/usr/lib). Required.
target_libdir="${1:?usage: build_musl_rv64im.sh <target-usr-lib-dir> [aports-ref]}"
aports_ref="${2:-master}"

cross="${CROSS_COMPILE:-riscv64-linux-gnu-}"
march="-march=rv64im -mabi=lp64 -mno-relax -O2 -fno-stack-protector"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- 1. sparse-checkout only main/musl from aports (no full clone) -----------
echo "Fetching Alpine musl aport (ref: $aports_ref)"
git -C "$work" clone --no-checkout --depth 1 --filter=blob:none \
    -b "$aports_ref" https://gitlab.alpinelinux.org/alpine/aports.git aports
git -C "$work/aports" sparse-checkout set --no-cone main/musl
git -C "$work/aports" checkout >/dev/null 2>&1
aport="$work/aports/main/musl"

pkgver="$(sed -n 's/^pkgver=//p' "$aport/APKBUILD")"
echo "Alpine musl pkgver: $pkgver"

# --- 2. fetch the exact upstream tarball the aport pins ----------------------
curl -sSL "https://musl.libc.org/releases/musl-$pkgver.tar.gz" \
    -o "$work/musl.tar.gz"
tar xzf "$work/musl.tar.gz" -C "$work"
src="$work/musl-$pkgver"

# --- 3. apply the aport's patch set in source= order, then ours -------------
echo "$pkgver" > "$src/VERSION"
patches="$(awk '/^source=/{f=1} f{print} f&&/"[[:space:]]*$/{exit}' "$aport/APKBUILD" \
           | grep -oE '[A-Za-z0-9._-]+\.patch')"
for p in $patches; do
    echo "  patch: $p"
    patch -d "$src" -p1 --silent < "$aport/$p"
done
echo "  patch: atomic_arch_rv64im.patch (ours)"
patch -d "$src" -p1 --silent < "$TOP_DIR/musl/atomic_arch_rv64im.patch"

# --- 4. build rv64im ---------------------------------------------------------
pushd "$src" >/dev/null
    CC="${cross}gcc" CFLAGS="$march" \
        ./configure --target=riscv64 --disable-shared --prefix="$work/out" >/dev/null
    make AR="${cross}ar" RANLIB="${cross}ranlib" -j"$(nproc)" >/dev/null
    make AR="${cross}ar" RANLIB="${cross}ranlib" install >/dev/null
popd >/dev/null

# --- 5. gate: no compressed / atomic instructions may have survived ----------
OBJDUMP="${cross}objdump" python3 "$TOP_DIR/tools/musl_isa_scan.py" \
    "$work/out/lib/libc.a" "$work/out/lib/crt1.o" \
    "$work/out/lib/crti.o" "$work/out/lib/crtn.o"

# --- 6. install over the stock rv64gc musl ----------------------------------
mkdir -p "$target_libdir"
cp "$work/out/lib/libc.a" "$target_libdir/"
for o in crt1 crti crtn Scrt1 rcrt1; do
    [ -f "$work/out/lib/$o.o" ] && cp "$work/out/lib/$o.o" "$target_libdir/"
done
echo "Installed rv64im musl (libc.a + crt) into $target_libdir"
