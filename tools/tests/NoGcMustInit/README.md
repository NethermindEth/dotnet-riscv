# JitZkNoGcMustInit zero-init regression

Run with a RISC-V bflat toolchain built from this patch series and `qemu-riscv64`:

```sh
bash tools/tests/NoGcMustInit/run.sh
```

`BFLAT` and `QEMU` can override the executable paths. The runner builds the
program with `JitZkNoGcMustInit` off and on and runs both.

Without the knob the JIT omits the explicit zeroing of a local with GC references
(`default` of a struct, a `null` reference local, a stack-allocated object)
because the prolog zeroes it anyway. With the knob the prolog no longer
zeroes GC slots for the GC's sake, so these zero-inits must come back as explicit
stores. Each case runs in a `[SkipLocalsInit]` method right after a call that
fills the stack with non-zero garbage. The struct and reference cases read
through non-inlined helpers. The object stays within `NewObject`, allowing stack
allocation; volatile field reads prevent its zero checks from being folded away.
Success exits with code 0; a case that reads garbage prints its name and exits
with code 1. All three cases fail with the knob enabled on a negative-control
JIT that drops prolog zeroing but omits the `fgVarNeedsExplicitZeroInit` fix.

When changing the object case or updating the toolchain, inspect it with
`--codegenopt JitDisasm=Program:NewObject`: it must allocate the object in the
stack frame, retain loads of its fields, and make no heap-allocation call.
