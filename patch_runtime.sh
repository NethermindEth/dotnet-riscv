#!/bin/bash

top_dir="$(pwd)"

pushd dotnet/src/runtime
    for file in $(ls ${top_dir}/patches/bflat-runtime/*.patch | xargs) ; do
        echo Applying $file
        patch -p1 < $file
    done
popd
