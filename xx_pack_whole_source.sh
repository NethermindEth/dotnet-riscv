#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

cd "${TOP_DIR}"

tar czvf whole_source.tar.gz *
