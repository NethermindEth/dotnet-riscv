#!/bin/bash

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

# Repoint the Alpine package mirror at the bflat-hosted one. Done with sed (not a
# context hunk in 12_alpine_custom.patch) so it survives http/https flips and line
# drift in arcade's build-rootfs.sh across VMR bumps. Idempotent.
substitute_alpine_mirror() {
    sed -i -E \
        -e 's#-X "https?://dl-cdn\.alpinelinux\.org/alpine/\$version/main"#-X "https://opensource.interpretica.io/bflat/alpine/a1/main"#g' \
        -e '\#-X "https?://dl-cdn\.alpinelinux\.org/alpine/\$version/community"#d' \
        "$1"
}

pushd dotnet > /dev/null 2> /dev/null

br_path="eng/common/cross/build-rootfs.sh"
patch -p1 < "${TOP_DIR}/patches/bflat-runtime/12_alpine_custom.patch"
if [ "$?" != "0" ] ; then
    echo "Failed to apply alpine patch (1)" >&2
    exit 1
fi
substitute_alpine_mirror "$br_path"

for folder in $(ls src) ; do
    if [ ! -d src/$folder ] || [ "$folder" == "command-line-api" ] || [ "$folder" == "razor" ] ; then
        continue
    fi
    pushd src/$folder > /dev/null 2> /dev/null
    if [ -f $br_path ] ; then
        echo Project: $folder
        patch -p1 < "${TOP_DIR}/patches/bflat-runtime/12_alpine_custom.patch"
        if [ "$?" != "0" ] ; then
            echo "Failed to apply alpine patch (2)" >&2
            exit 2
        fi
        substitute_alpine_mirror "$br_path"
    fi
    popd > /dev/null 2> /dev/null
done
popd > /dev/null 2> /dev/null