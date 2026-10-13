#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
# SPDX-License-Identifier: MIT

set -euo pipefail

test_dir="$(cd "$(dirname "$0")" && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

"${BFLAT:-bflat}" build "$test_dir/Program.cs" -o "$out/inline-box" \
    --arch riscv64 --os linux --libc zisk_sim --no-pie --no-pthread \
    --no-globalization --no-stacktrace-data --no-reflection -Ot \
    --codegenopt JitZkBumpAddr=bffefff8
"${QEMU:-qemu-riscv64}" "$out/inline-box"
