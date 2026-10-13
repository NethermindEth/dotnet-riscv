# RISC-V allocation regression

Run against a patched .NET 10 or 11 `dotnet/runtime` source tree:

```sh
python3 tools/tests/AllocFast/run.py /path/to/runtime
```

Requires `riscv64-linux-gnu-gcc` and `qemu-riscv64`; override them with `--cc`
and `--runner` (use `--runner ''` on a RISC-V host).

The harness assembles the source tree's three array/string fast helpers and
their actual stack save/restore macros. It supplies a TLS resolver that
clobbers `t0` and a slow-path sentinel, without building the rest of the runtime.
Synthetic MethodTable and allocation-context offsets match the test's data.
The cases cover empty and nonempty allocations, alignment, exact fits,
insufficient space, preserved slow-path arguments and the next allocation.

All 24 cases must pass. Reverting the size spill/reload in `AllocFast.S` makes
the same harness fail; a resolver that happens to preserve `t0` cannot hide it.
