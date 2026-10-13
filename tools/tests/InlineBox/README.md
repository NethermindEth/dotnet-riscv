# Inline boxing regression

Run with a RISC-V bflat toolchain built from this patch series and `qemu-riscv64`:

```sh
bash tools/tests/InlineBox/run.sh
```

`BFLAT` and `QEMU` can override the executable paths. The runner selects
`zisk_sim` and explicitly enables `JitZkBumpAddr` at its fixed bump-cell address.
Running this program on a normal .NET runtime does not exercise the regression.

The test warms up hashing and boxing, then boxes an escaping 24-byte struct
immediately after allocating an object. It verifies both directions of the
overlap: writing the box must preserve the object's identity hash, and hashing
the object must preserve the box's last field. Success exits with code 0;
corruption exits with code 1. The same test must fail with the pre-fix JIT.
