# Strict alignment regression

Run with Python 3 and a C++17 compiler:

```sh
python3 tools/tests/StrictAlignment/test_shift_alignment.py --cxx g++
```

The test compiles the actual `GT_LSH` case extracted from perf-67 with minimal
IR stubs. It checks the claimed alignment against concrete shifted values for
32-bit and 64-bit operands, input alignments from 1 to 64 bytes, constant counts
from -128 to 128, and nonconstant counts. It also checks that the lowering phase
invokes the local analysis once.

In particular, an int32 shift by 32 or 33 must not prove 64-byte alignment:
those counts execute as shifts by 0 or 1. Testing the IR directly avoids C#
normalizing constant counts before they reach the JIT, and does not depend on
the host trapping unaligned loads. The original patch fails at int32 count 32.
Use `--patch /path/to/original.patch` to verify that failure.

This isolates the alignment proof; it does not build the complete JIT or run
generated RISC-V code on a strict-alignment target.
