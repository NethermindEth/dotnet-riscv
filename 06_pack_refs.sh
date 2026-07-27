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
    local pkgpath=".packages/microsoft.netcore.app.ref"

    if [ ! -d "${artifactpath}/$pkgpath" ] ; then
        return 1
    fi

    pushd "${artifactpath}"
        # The cache holds reference packs for several majors (6.0, 8.0, 9.0,
        # ... plus the freshly built one) — pick the highest version only,
        # a flat copy of all of them would mix and clobber same-named dlls.
        refdir="$(ls -d $pkgpath/*/ref/net[0-9]* 2>/dev/null | sort -V | tail -n1)"
        if [ -z "$refdir" ] ; then
            popd
            return 1
        fi
        cp "$refdir"/*.dll \
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


pack_bflat_refs "$file" "${output_dir}" "${TOP_DIR}/dotnet"
exit $?
