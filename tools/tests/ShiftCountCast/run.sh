#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
# SPDX-License-Identifier: MIT

set -euo pipefail

test_dir="$(cd "$(dirname "$0")" && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
elf="$out/shiftcount"

"${BFLAT:-bflat}" build "$test_dir/Program.cs" -o "$elf" \
    --arch riscv64 --os linux --libc musl --no-pie --no-pthread --no-reflection -Ot
"${QEMU:-qemu-riscv64}" "$elf"

check_shift() {
    local method="$1" opcode="$2" disasm
    disasm="$("${OBJDUMP:-riscv64-linux-gnu-objdump}" -d --disassemble="shiftcount_Program__${method}" "$elf")"
    if ! grep -Eq "[[:space:]]${opcode}[[:space:]]" <<<"$disasm" ||
        grep -Eq '[[:space:]]sext\.w[[:space:]]' <<<"$disasm"; then
        printf '%s\n' "$disasm" >&2
        return 1
    fi
}

check_shift Shift64 srl
check_shift Shift32 sllw
