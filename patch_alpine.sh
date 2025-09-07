#!/bin/bash

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

pushd dotnet > /dev/null 2> /dev/null

br_path="eng/common/cross/build-rootfs.sh"
patch -p1 < "${TOP_DIR}/patches/bflat-runtime/12_alpine_custom.patch"

for folder in $(ls src) ; do
    if [ ! -d src/$folder ] || [ "$folder" == "command-line-api" ] || [ "$folder" == "razor" ] ; then
        continue
    fi
    pushd src/$folder > /dev/null 2> /dev/null
    if [ -f $br_path ] ; then
        echo Project: $folder
        patch -p1 < "${TOP_DIR}/patches/bflat-runtime/12_alpine_custom.patch"
    fi
    popd > /dev/null 2> /dev/null
done
popd > /dev/null 2> /dev/null