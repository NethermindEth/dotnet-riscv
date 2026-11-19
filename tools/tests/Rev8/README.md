# rev8 for ReverseEndianness on riscv32

Run with a bflat toolchain that has both RISC-V targets, built from this patch
series, and an `llvm-objdump` that knows Zbb:

```sh
python3 tools/tests/Rev8/run.py
```

`BFLAT` and `OBJDUMP` can override the executable paths.

The test compiles a 32-bit `BinaryPrimitives.ReverseEndianness` for riscv32 and
riscv64 with `JitZkRev8` off and on, and looks for `rev8` in the code of the
method: only riscv32 with `JitZkRev8=1` has it.
