#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

libs_dir="${TOP_DIR}/libs"
output_dir="${TOP_DIR}/output/bflat-refs"
file="bflat-refs.zip"

cd "${TOP_DIR}"

mkdir -p "${output_dir}"

function pack_bflat_refs()
{
    local file="$1"
    local output_dir="$2"
    local artifactpath="$3"

    if [ ! -d "${artifactpath}/bin/ref/net10.0" ] ; then
        return 1
    fi

    pushd "${artifactpath}"
        cp ./bin/ref/net10.0/*.dll \
           "${output_dir}/"
    popd

    ret="1"
    pushd "${output_dir}"
        if [ -f "$file" ] ; then
            rm "$file"
        fi
        zip -r "$file" *
        ret="$?"
    popd

    return $ret
}


pack_bflat_refs "$file" "${output_dir}" "${TOP_DIR}/dotnet/artifacts" || \
pack_bflat_refs "$file" "${output_dir}" "${TOP_DIR}/dotnet/src/runtime/artifacts"
exit $?
