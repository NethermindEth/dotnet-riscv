# JitZkNoGcMustInit zero-init regression

Run with a RISC-V bflat toolchain built from this patch series and `qemu-riscv64`:

```sh
bash tools/tests/NoGcMustInit/run.sh
```

`BFLAT` and `QEMU` can override the executable paths. The runner builds the
program with `JitZkNoGcMustInit` off and on and runs both.

Without the knob the JIT omits the explicit zeroing of a local with GC references
(`default` of a struct, a `null` reference local, a new object if it is stack
allocated) because the prolog zeroes it anyway. With the knob the prolog no longer
zeroes GC slots for the GC's sake, so these zero-inits must come back as explicit
stores. Each case runs in a `[SkipLocalsInit]` method right after a call that
fills the stack with non-zero garbage, and reads the local through code that
cannot see the zeroing. Success exits with code 0; a case that reads garbage
prints its name and exits with code 1. The first two cases fail with a JIT that
drops the prolog zeroing but still omits the explicit stores.
