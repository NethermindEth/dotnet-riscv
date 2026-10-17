#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
# SPDX-License-Identifier: MIT

set -euo pipefail

test_dir="$(cd "$(dirname "$0")" && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

# --libc sp1 turns on JitNoUnalignedAccess and JitRiscV64StrictAlign.
"${BFLAT:-bflat}" build "$test_dir/Program.cs" -o "$out/fast-path" \
    --arch riscv64 --os linux --libc sp1 --no-pie --no-pthread \
    --no-globalization --no-stacktrace-data --ldflags=--strip-all -Ot
: > "$out/input.bin"
# SP1 fails the execution on any misaligned access; the runner exits non-zero when the guest does.
docker run --rm --shm-size=8g --mount "type=bind,source=$out,target=/n" \
    "${SP1_RUNNER_IMAGE:-nethermindeth/sp1-runner:v6.6.0}" /n/fast-path /n/input.bin
