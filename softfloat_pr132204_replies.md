# Draft replies for dotnet/runtime#132204 (not posted)

## To @am11 (cpufeatures.c / baseline / A)

> I suggest to adapt to the existing cpufeatures.c approach

Agreed for everything that has a choice at compile time: the follow-up models
F, D, C and A as riscv64 `InstructionSet`s (D implies F), seeds the rv64gc
baseline from them, gates the JIT emitter on them like x64/arm64 gate their
optional ISAs, and ties the hwprobe assertion in `cpufeatures.c` to the
build's `-march` instead of asserting the full baseline. The `.S` sources are
the one place without that choice - the assembler is the consumer - so they
switch on the predefined `__riscv_*` macros, which are what `-march` sets.
Happy to move them to a single `RISCV_ISA_*` header derived from the same
place if that reads better.

> I'm not sure if we want to lower the baseline

Not proposed. rv64gc stays the baseline and the default; the reduced ISA is
a separately selected target (`--targetarch riscv64-lp64` in the follow-up,
following armel), and a hard-float target missing F or D is rejected with a
diagnostic rather than accommodated.

> marking `A` as optional

Understood that this is the hardest part. The fallback is only selected when
the target says so, and the target (a zkVM guest) is single-threaded and
deterministic by construction - there is no observer that can distinguish the
sequence from an atomic. If it helps, the target definition can carry that
property explicitly (the design issue asks exactly this) instead of
`__riscv_atomic` alone.

## To @tannergooding (software FP / scope / fork)

> This would require a substantial amount of code ... to handle full and
> proper emulation of float/double arithmetic

That is what we deliberately did not do. No FP arithmetic is implemented in
the runtime or the libraries: the JIT emits calls to 14 helpers that ilc binds
to the toolchain's compiler-rt builtins (`__adddf3`, `__ledf2`, ...), the same
way `fmod`/`fmodf` are bound today. CoreLib is untouched and there are no
`#if` paths in managed code. The JIT part is ~450 lines, entirely under
`TARGET_RISCV64` + the soft-float flag, and reuses the existing expansion
hooks (`USE_HELPER_FOR_ARITH` as on 32-bit for `long`, `fgCastRequiresHelper`
as on x86, the armel ABI flag); the IR keeps its FP types and only the
register class of `TYP_FLOAT`/`TYP_DOUBLE` changes.

> a scenario that not even Linux supports

The lp64 (soft-float) ABI is a standard RISC-V psABI ABI that gcc/clang and
musl support; what Linux distributions do not ship is a userland for it. We
build that userland downstream. The runtime and the compiler are the parts
that cannot be built downstream, which is why only they are proposed here.

> significant design as well as weigh-in from all the respective owners

Agreed - that is why the code generation half is a design issue first
(link), with the exact list of what is and is not touched, rather than a PR.

> whether it's something that is more appropriate to exist entirely in a
> custom fork

We run from a fork today. The reason to ask for upstream is that the pieces
involved are the ABI and the register-class model, which cannot be provided
as an add-on, and that every other part of the environment already stays
downstream.
