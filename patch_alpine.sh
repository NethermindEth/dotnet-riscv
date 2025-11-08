#!/bin/bash

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

pushd dotnet > /dev/null 2> /dev/null

br_path="eng/common/cross/build-rootfs.sh"
patch -p1 < "${TOP_DIR}/patches/bflat-runtime/12_alpine_custom.patch"
if [ "$?" != "0" ] ; then
    echo "Failed to apply alpine patch (1)" >&2
    exit 1
fi

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
    fi
    popd > /dev/null 2> /dev/null
done
popd > /dev/null 2> /dev/null