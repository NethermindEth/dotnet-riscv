#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
# SPDX-License-Identifier: MIT

"""Exercise the runtime's RISC-V array allocation assembly with hostile TLS."""

import argparse
from pathlib import Path
import re
import subprocess
import tempfile


def macro(source, name):
    match = re.search(r"^\s*\.macro " + name + r"\b.*?^\s*\.endm\b", source, re.M | re.S)
    if match is None:
        raise ValueError(f"Missing assembly macro {name}")
    return match.group(0)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("runtime", type=Path, help="dotnet/runtime source tree, after applying patches")
parser.add_argument("--cc", default="riscv64-linux-gnu-gcc")
parser.add_argument("--runner", default="qemu-riscv64", help="empty for native RISC-V")
args = parser.parse_args()
tests = Path(__file__).resolve().parent
coreclr = args.runtime.resolve() / "src/coreclr"
allocation = (coreclr / "runtime/riscv64/AllocFast.S").read_text()
macros = (coreclr / "pal/inc/unixasmmacrosriscv64.inc").read_text()

# Use the production save/restore macros and complete fast helper bodies;
# only the allocation context provider and slow helpers are test doubles.
names = ("LEAF_ENTRY", "LEAF_END", "PROLOG_SAVE_REG_PAIR_INDEXED",
         "PROLOG_SAVE_REG_PAIR", "EPILOG_RESTORE_REG_PAIR_INDEXED",
         "EPILOG_RESTORE_REG_PAIR")
assembly = "\n".join(macro(macros, name) for name in names)
assembly += "\n" + macro(allocation, "NEW_ARRAY_FAST")
for name in ("RhNewString", "RhpNewArrayFast", "RhpNewPtrArrayFast"):
    match = re.search(r"^\s*LEAF_ENTRY " + name + r",.*?^\s*LEAF_END " + name + r",[^\n]*",
                      allocation, re.M | re.S)
    if match is None:
        raise ValueError(f"Missing allocation helper {name}")
    assembly += "\n" + match.group(0)

with tempfile.TemporaryDirectory(prefix="allocfast-regression-") as temp:
    out = Path(temp)
    (out / "allocfast.inc").write_text(assembly + "\n")
    binary = out / "allocfast"
    subprocess.run([args.cc, "-O2", "-static", "-no-pie", "-I", str(out),
                    str(tests / "test.c"), str(tests / "test.S"), "-o", str(binary)], check=True)
    subprocess.run(([args.runner] if args.runner else []) + [str(binary)], check=True)
