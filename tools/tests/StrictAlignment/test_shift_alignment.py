#!/usr/bin/env python3
"""Exercise perf-67's actual GT_LSH alignment proof with minimal IR stubs."""

import argparse
import os
from pathlib import Path
import subprocess
import tempfile


DEFAULT_PATCH = (Path(__file__).resolve().parents[3] /
                 "fixup/11/profile/upstream/perf-67_riscv64_strict_align_locals.patch")

HARNESS = r"""
#include <algorithm>
#include <cstdint>
#include <iostream>
using std::min;
using ssize_t = intptr_t;
enum { GT_LSH };
struct GenTree
{
    unsigned bytes, alignment;
    ssize_t count;
    bool constant;
    GenTree *operand, *shift;
    unsigned TypeGet() { return bytes; }
    GenTree* gtGetOp1() { return operand; }
    GenTree* gtGetOp2() { return shift; }
    bool IsCnsIntOrI() { return constant; }
    GenTree* AsIntCon() { return this; }
    ssize_t IconValue() { return count; }
};
unsigned genTypeSize(unsigned type) { return type; }
unsigned KnownAlignmentLog2(GenTree* node, int depth = 0)
{
    if (node->operand == nullptr)
        return node->alignment;
    const unsigned maxLog2 = 6;
    switch (GT_LSH)
    {
        // SHIFT_CASE
    }
    return 0;
}
int main()
{
    unsigned cases = 0;
    for (unsigned bytes : {4u, 8u})
    for (unsigned alignment = 0; alignment <= 6; alignment++)
    for (ssize_t count = -128; count <= 128; count++)
    {
        GenTree operand{bytes, alignment, 0, false, nullptr, nullptr};
        GenTree shift{4, 0, count, true, nullptr, nullptr};
        GenTree node{bytes, 0, 0, false, &operand, &shift};
        unsigned proven = KnownAlignmentLog2(&node);
        // A concrete operand with exactly the promised alignment. IL shifts mask
        // the count to five bits for int32 and six bits for int64/native int.
        uint64_t value = (uint64_t{1} << alignment) << (count & (bytes * 8 - 1));
        if (bytes == 4)
            value = static_cast<uint32_t>(value);
        if (proven > 6 || (value & ((uint64_t{1} << proven) - 1)) != 0)
        {
            std::cerr << "Unsound alignment: width=" << bytes * 8
                      << " input alignment=" << alignment << " count=" << count
                      << " proven=" << proven << " value=" << value << '\n';
            return 1;
        }
        shift.constant = false;
        if (KnownAlignmentLog2(&node) != 0)
            return 2;
        cases += 2;
    }
    std::cout << cases << " shift alignment cases passed.\n";
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--patch", type=Path, default=DEFAULT_PATCH)
    parser.add_argument("--cxx", default=os.environ.get("CXX", "c++"))
    args = parser.parse_args()
    # Reconstruct the new side of the hunks; do not copy the proof into the test.
    lines = args.patch.read_text().splitlines()
    source = "\n".join(line[1:] for line in lines
                       if line.startswith(("+", " ")) and not line.startswith("+++"))
    start = source.index("        case GT_LSH:")
    end = source.index("        case GT_LEA:", start)
    with tempfile.TemporaryDirectory(prefix="strict-alignment-") as directory:
        cpp = Path(directory) / "shift.cpp"
        exe = Path(directory) / ("shift.exe" if os.name == "nt" else "shift")
        cpp.write_text(HARNESS.replace("// SHIFT_CASE", source[start:end]))
        subprocess.run([args.cxx, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                        str(cpp), "-o", str(exe)], check=True)
        subprocess.run([str(exe)], check=True)

    calls = sum(line.strip() == "ComputeAlignedLocals();" for line in source.splitlines())
    assert calls == 1, f"Expected one alignment analysis, found {calls}"
    print("Single alignment analysis invocation verified.")


if __name__ == "__main__":
    main()
