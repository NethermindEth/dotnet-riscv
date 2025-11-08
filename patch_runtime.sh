#!/bin/bash

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

pushd dotnet/src/runtime
    for file in $(ls ${TOP_DIR}/patches/bflat-runtime/*.patch | xargs) ; do
        echo Applying $file
        patch -p1 < $file
        if [ "$?" != "0" ] ; then
            echo Failed to apply patch $file >&2
            exit 1
        fi
    done
popd
