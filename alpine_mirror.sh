#!/bin/bash
# Shared by patch_alpine.sh (the VMR checkout) and 00_build_rootfs.sh (its own
# runtime clone): both build an Alpine rootfs and both need it to come from the
# rv64ima mirror rather than the stock hard-float feed.

# Repoint the Alpine package mirror at the bflat-hosted one. Done with sed rather
# than a context hunk in fixup/rootfs/alpine_custom.patch so that it survives line
# drift in arcade's build-rootfs.sh across VMR bumps. Idempotent.
#
# The mirror serves a single rv64ima "b8" repository - no per-Alpine-version
# directory and no community - so the $version component is dropped and the
# community repositories are removed rather than repointed.
#
# apk-tools-static is the exception: it is the host's x86_64 apk binary, which
# runtime's build-rootfs.sh now fetches from "$__AlpineRepo/v3.20/main/$arch/"
# instead of gitlab. The mirror is a flat rv64ima feed and carries no such
# package, so that one URL stays on the stock CDN; a 404 there leaves an empty
# rootfs, and the release that follows is missing libgcc.a, libm.a and libdl.a.
#
# Arcade has since moved the URL into a variable:
#     __AlpineRepo="${__AlpineRepoOverride:-https://dl-cdn.alpinelinux.org/alpine}"
#     -X "$__AlpineRepo/$version/main"
# so the substitution targets that assignment and the "$version" component. The
# older literal form is still handled, for a VMR that predates the change.
#
# The stock CDN keeps only the newest apk-tools-static build, so runtime's pin
# breaks each time Alpine rebuilds it: 3.0.8-r0 went away for 3.0.9-r0. The pin
# and its SHA-512 sums are moved forward only when they still name 3.0.8-r0,
# so a runtime that bumps the pin itself is left alone.
substitute_alpine_mirror() {
    sed -i -E \
        -e 's#^[[:space:]]*__AlpineRepo=.*#__AlpineRepo="https://opensource.interpretica.io/bflat/alpine/b8"#' \
        -e 's#-X "\$__AlpineRepo/\$version/main"#-X "$__AlpineRepo/main"#g' \
        -e '\#-X "\$__AlpineRepo/\$version/community"#d' \
        -e 's#__ApkToolsUrl="\$__AlpineRepo/#__ApkToolsUrl="https://dl-cdn.alpinelinux.org/alpine/#' \
        -e 's#^([[:space:]]*__ApkToolsVersion=)3\.0\.8-r0$#\13.0.9-r0#' \
        -e 's#6ab4f5e521efbfff75a4b0ecc6a028b4df0c22eadc46c18a30fa03faca0f6efd6c546b3682a856e66865f0152993a9cc843c15633a7d01b6e0f9d225b1e31ef8#c97f27bef2940bb6c23323bf9fe0f3c60932a3c676f1cea23d5f5664ee8be27f349bb0c905f5f3e1fe0b04cfd79d6e422829c49b12cacbce21b02d9b2d1fa083#' \
        -e 's#c592bfefe3b3bc73d56fef5293a2c5c27a71d0555df7ca7db638a70c7ac81be6509f6348f28fe7474ae9adbda6f21c00a8c20d8a6ba6d5579f2ffa78d55184d2#121b77c2e1ac3c856e168c335d57887ab9716bf6b704e30309c37cf8d0935f72a1775aa6628ec1f73eeec0ca7282f4b40836887e62dac94063485b496ad460c9#' \
        -e 's#-X "https?://dl-cdn\.alpinelinux\.org/alpine/\$version/main"#-X "https://opensource.interpretica.io/bflat/alpine/b8/main"#g' \
        -e '\#-X "https?://dl-cdn\.alpinelinux\.org/alpine/\$version/community"#d' \
        "$1"
}
