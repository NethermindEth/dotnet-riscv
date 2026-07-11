#!/bin/bash
#
# Plants a fake GSSAPI/Kerberos into the cross rootfs so the unmodified
# System.Net.Security.Native shim builds against a minimal, soft-float rootfs
# that carries no real krb5.
#
# This is deliberately NOT a runtime source patch. On Linux the shim is built
# with -DGSS_SHIM: it never links libgssapi_krb5, it dlopen()s it on first use
# and tolerates its absence (see extra_libs.cmake). So at build time only two
# things are actually required, both satisfiable from outside the tree:
#
#   1. The MIT krb5 gssapi headers, to compile pal_gssapi.c. These are
#      architecture-independent, so we lift them verbatim from the upstream
#      Alpine krb5-dev / e2fsprogs-dev (com_err) packages.
#   2. Something for cmake's find_library(gssapi_krb5) gate to find. Its result
#      is discarded on Linux (the link uses -ldl, not -lgssapi), so an empty
#      soft-float stub .so is enough — it is never linked and, unless an app
#      actually performs Negotiate auth, never loaded.
#
# The stub's soname matches the runtime dlopen target ("libgssapi_krb5.so.2").
# dlsym on it returns NULL for every gss_* entry, so Negotiate/Kerberos degrades
# to "unavailable" rather than misbehaving.
set -euo pipefail

ROOTFS="${ROOTFS_DIR:?ROOTFS_DIR must point at the cross rootfs}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
ALPINE_BRANCH="${ALPINE_BRANCH:-edge}"
ALPINE_ARCH="${ALPINE_ARCH:-riscv64}"
CC="${GSS_STUB_CC:-clang}"
command -v "$CC" >/dev/null 2>&1 || CC=clang-20

base="${ALPINE_MIRROR}/${ALPINE_BRANCH}/main/${ALPINE_ARCH}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- 1. headers (arch-independent) -----------------------------------------
fetch_headers() {
    local pkg="$1"
    local apk
    apk="$(curl -fsSL "${base}/" | grep -oE "${pkg}-[0-9][^\"<]*\.apk" | head -1)"
    [ -n "$apk" ] || { echo "provision_gss_stub: cannot locate $pkg on $base" >&2; exit 1; }
    echo "provision_gss_stub: fetching headers from $apk"
    curl -fsSL "${base}/${apk}" -o "${work}/${pkg}.apk"
    tar -xzf "${work}/${pkg}.apk" -C "$work" 'usr/include' 2>/dev/null || true
    cp -a "${work}/usr/include/." "${ROOTFS}/usr/include/"
    rm -rf "${work}/usr/include"
}

fetch_headers krb5-dev        # gssapi/*.h, krb5.h, profile.h
fetch_headers e2fsprogs-dev   # et/com_err.h, com_err.h (pulled in by krb5.h)

# --- 2. find_library gate: empty soft-float stub ---------------------------
echo "provision_gss_stub: building stub libgssapi_krb5.so.2 with $CC"
: > "${work}/stub.c"
"$CC" --target="${ALPINE_ARCH}-alpine-linux-musl" \
      -march=rv64ima -mabi=lp64 \
      -shared -fPIC -nostdlib -fuse-ld=lld \
      -Wl,-soname,libgssapi_krb5.so.2 \
      -x c "${work}/stub.c" \
      -o "${ROOTFS}/usr/lib/libgssapi_krb5.so.2"
ln -sf libgssapi_krb5.so.2 "${ROOTFS}/usr/lib/libgssapi_krb5.so"

echo "provision_gss_stub: done"
