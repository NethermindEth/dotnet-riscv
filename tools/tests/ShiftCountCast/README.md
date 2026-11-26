# Shift-count cast regression

Run with a RISC-V bflat toolchain built from this patch series and `qemu-riscv64`:

```sh
bash tools/tests/ShiftCountCast/run.sh
```

`BFLAT`, `QEMU` and `OBJDUMP` can override the executable paths.

Each shift method narrows a `long` count with `unchecked((int)count)`. The runner
first runs the program. Each of the six register shifts (`sll`, `srl`, `sra`,
`sllw`, `srlw`, `sraw`) is compared with values computed on x64 with a stock JIT.
Exit codes:

- 0: success.
- 1: a shift, or a narrowed count used outside a shift, gives a wrong result.
- 2: a checked narrowing that does not overflow gives a wrong result.
- 3: a checked narrowing that overflows does not throw `OverflowException`.

The runner then disassembles each shift method. A method must contain its
shift instruction and no `sext.w`. The JIT before perf-99 passes the run and
fails the disassembly check: it emits `sext.w` before each of the six shifts.
