#!/bin/bash
# Shared by build_musl_rv32im.sh and build_musl_rv64im.sh: both build musl from
# its release tarball, which musl.libc.org alone serves upstream, and a build
# fails whenever that host is down.

# fetch_musl <version> <output> <sha bits> <hash>: downloads musl-<version>.tar.gz
# to <output> from musl.libc.org, or from a mirror when that fails, and keeps the
# first copy whose SHA-<bits> is <hash>. The mirrors are Buildroot's source
# cache and the Debian archive (the .orig.tar.gz of the musl package is the
# release tarball itself); the hash makes the source irrelevant.
fetch_musl() {
    local version="$1" out="$2" bits="$3" hash="$4" url actual
    for url in \
        "https://musl.libc.org/releases/musl-$version.tar.gz" \
        "https://sources.buildroot.net/musl/musl-$version.tar.gz" \
        "https://deb.debian.org/debian/pool/main/m/musl/musl_$version.orig.tar.gz" ; do
        if ! curl -fsSL --connect-timeout 30 --retry 2 "$url" -o "$out" ; then
            echo "warning: cannot download $url" >&2
            continue
        fi
        actual="$(sha${bits}sum "$out" 2>/dev/null || shasum -a "$bits" "$out")"
        [ "${actual%% *}" = "$hash" ] && return 0
        echo "warning: $url: sha$bits ${actual%% *}, expected $hash" >&2
    done
    echo "musl-$version.tar.gz: no source has it with sha$bits $hash" >&2
    return 1
}
