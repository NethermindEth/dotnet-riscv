#!/bin/bash

export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

pushd dotnet/src/runtime
    for file in $(ls ${TOP_DIR}/patches/bflat-runtime/*.patch | xargs) ; do
        echo Applying $file
        patch -p1 < $file
    done
popd
