#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"
export DEBIAN_FRONTEND=noninteractive

output_file="compiler-linux-glibc-x64.zip"

apt-get update -y
apt-get install -y llvm-20 lld-20 patchelf binutils zip

output="${TOP_DIR}/output/compiler-linux"
mkdir -p "${output}"

pushd /usr/lib/x86_64-linux-gnu
cp libffi.so* "$output/"
cp libedit.so.2* "$output/"
cp libxml2.so* "$output/"
popd

pushd /usr/lib/llvm-20/lib
cp libLLVM.so* "$output/"
popd

pushd /usr/lib/llvm-20/bin
cp lld "$output/"
cp llvm-objcopy "$output/"
popd

pushd "$output"
	patchelf --set-rpath '$ORIGIN' *
	if [ -f "$output_file" ] ; then
		rm "$output_file"
	fi
	zip -r "$output_file" *
popd

exit $?