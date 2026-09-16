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
substitute_alpine_mirror() {
    sed -i -E \
        -e 's#^[[:space:]]*__AlpineRepo=.*#__AlpineRepo="https://opensource.interpretica.io/bflat/alpine/b8"#' \
        -e 's#-X "\$__AlpineRepo/\$version/main"#-X "$__AlpineRepo/main"#g' \
        -e '\#-X "\$__AlpineRepo/\$version/community"#d' \
        -e 's#__ApkToolsUrl="\$__AlpineRepo/#__ApkToolsUrl="https://dl-cdn.alpinelinux.org/alpine/#' \
        -e 's#-X "https?://dl-cdn\.alpinelinux\.org/alpine/\$version/main"#-X "https://opensource.interpretica.io/bflat/alpine/b8/main"#g' \
        -e '\#-X "https?://dl-cdn\.alpinelinux\.org/alpine/\$version/community"#d' \
        "$1"
}
