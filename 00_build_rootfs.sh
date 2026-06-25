#!/bin/bash
export TOP_DIR="$(cd "$(dirname "$(which "$0")")" ; pwd -P)"

tmp_dir="${TOP_DIR}/tmp/rootfs"

# Source for build-rootfs.sh: the SAME dotnet VMR fork/branch the rest of the
# build uses (CI job inputs), so the rootfs is built with the matching
# build-rootfs.sh (and patch 12 context lines up). Falls back to the workflow
# defaults when run locally without the env set.
ROOTFS_FORK="${ROOTFS_FORK:-dotnet}"
ROOTFS_BRANCH="${ROOTFS_BRANCH:-release/10.0.1xx}"

apt-get update -y
apt-get install -y xz-utils git debootstrap libc6-riscv64-cross qemu-user-static binfmt-support python3-pip
pip3 install aiohttp

cd "${TOP_DIR}"

mkdir -p "${tmp_dir}"

pushd "${tmp_dir}"
    # Clone the VMR at the requested fork/branch. Checked out as "runtime" so the
    # downstream tmp/rootfs/runtime/.tools/rootfs/... paths (03/04 pack scripts)
    # keep working; the VMR carries eng/common/cross/build-rootfs.sh at its root.
    echo "Cloning ${ROOTFS_FORK}/dotnet @ ${ROOTFS_BRANCH} for build-rootfs.sh"
    git clone --single-branch --depth 1 -b "${ROOTFS_BRANCH}" \
        "https://github.com/${ROOTFS_FORK}/dotnet" runtime || exit 1
    pushd runtime
        # Fail loudly if patch 12 does not apply (a silent failure here used to
        # fall back to stock dl-cdn Alpine, shipping double-float musl).
        patch -p1 < "${TOP_DIR}/patches/bflat-runtime/12_alpine_custom.patch" || exit 1
        echo Preparing GNU rootfs
        ./eng/common/cross/build-rootfs.sh riscv64 noble --skipemulation --skipunmount --rootfsdir $(pwd)/.tools/rootfs/riscv64-gnu
        echo Preparing musl rootfs
        ./eng/common/cross/build-rootfs.sh riscv64 alpineedge --skipemulation --skipunmount --rootfsdir $(pwd)/.tools/rootfs/riscv64-musl
    popd
popd
