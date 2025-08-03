#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"
export DEBIAN_FRONTEND=noninteractive

output_file="compiler-linux-glibc-x64.zip"

apt-get update -y
apt-get install -y llvm-18 lld-18 patchelf binutils zip

output="${TOP_DIR}/output/compiler-linux"
mkdir -p "${output}/bin"

pushd /usr/lib/x86_64-linux-gnu
cp libffi.so* "$output/bin"
cp libedit.so.2* "$output/bin"
cp libxml2.so* "$output/bin"
popd

pushd /usr/lib/llvm-18/lib
cp libLLVM.so* "$output/bin"
popd

pushd /usr/lib/llvm-18/bin
cp lld "$output/bin"
cp llvm-objcopy "$output/bin"
popd

pushd "$output"
	patchelf --set-rpath '$ORIGIN' bin/*
	if [ -f "$output_file" ] ; then
		rm "$output_file"
	fi
	zip -r "$output_file" *
popd

exit $?