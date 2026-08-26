# [RFC] Soft-float RISC-V target for NativeAOT (riscv64-lp64)

*Draft of the dotnet/runtime design issue. Not filed yet.*

## Summary

Add a soft-float RISC-V target to NativeAOT: the `lp64` calling convention
(no F/D extensions) as an explicit target ABI, with floating-point arithmetic
compiled to calls into the C toolchain's compiler-rt builtins. The normal
`rv64gc`/`lp64d` configuration is unchanged; every new code path is behind
the ABI selection and evaluates to today's behaviour otherwise.

This is the code-generation half of the story started in #132204 (building
the runtime assembly without F/D, A and C). It is posted as a design issue
first, as requested there, so that the shape can be agreed before a PR.

## Who needs it

zkVM guests execute a fixed, deterministic RISC-V subset (the zkEVM target
standard: rv64im, no A/C/F/D). Nethermind compiles its Ethereum execution
client to such guests with NativeAOT today, through a downstream toolchain
(nethermindeth/bflat-riscv64, nethermindeth/dotnet-riscv). Everything that is
specific to the environment - libc, the zkVM system interface, the soft-float
libm, the link step - stays downstream. What cannot stay downstream is the
compiler: the ABI and the JIT's register-class model are not pluggable.

## What is *not* proposed

* **No software floating-point implementation in the runtime or libraries.**
  The arithmetic is delegated to the toolchain's compiler-rt/libgcc builtins
  (`__adddf3`, `__ledf2`, ...), exactly as `Math.IEEERemainder`-style helpers
  already delegate `fmod`/`fmodf` to libm. `System.Private.CoreLib` is not
  touched; no `#if` paths in managed code.
* **No change to the rv64gc baseline.** The soft-float target is a separate,
  explicitly selected ABI (`--targetarch riscv64-lp64`, following the `armel`
  precedent), not a lowered default. Hard-float targets without F or D are
  rejected with a diagnostic rather than silently accommodated.
* **No claim of general-purpose support.** NativeAOT only; no CoreCLR VM
  support (the VM never selects the ABI), no crossgen2/ReadyToRun, no
  interpreter. The runtime helpers table carries `NULL` entries for the new
  helpers on the VM side, the way the 64-bit VM does for `CORINFO_HELP_LLSH`.

## Design

### 1. Instruction sets F/D/C/A (prerequisite, small)

Model the F, D, C and A extensions as `InstructionSet` entries for riscv64
(`InstructionSetDesc.txt`, D implies F), seed the rv64gc baseline from them,
and gate the emitter on them the way x64/arm64 gate optional ISAs. The
hwprobe assertion in `cpufeatures.c` is tied to the build's `-march`. This
replaces the ad-hoc `__riscv_*` checks with the mechanism @am11 pointed at.

### 2. Target ABI (small)

`TargetAbi.NativeAotRiscV64SoftFloat`, spelled `riscv64-lp64` on the ilc
command line. It drives:

* `CORJIT_FLAG_SOFTFP_ABI` (reused from armel) for the JIT;
* the RISC-V ELF `e_flags` float-ABI field (`ElfObjectWriter` currently
  writes `EF_RISCV_FLOAT_ABI_DOUBLE` unconditionally; the RVC bit is also made
  to follow the C instruction set);
* the instruction-set defaults (no D/F for the soft target) and a two-way
  check in `RyuJitCompilation`: lp64d requires F and D, lp64 must not have
  them (lp64f is not supported).

In the JIT, `compUseSoftFP` gates the ABI classifier (`RiscV64Classifier`,
`getReturnTypeForStruct`, `ReturnTypeDesc`) so that FP scalars and FP struct
fields take the integer calling convention - the same shape as armel.

### 3. Helpers (14)

`CORINFO_HELP_{FLT,DBL}{ADD,SUB,MUL,DIV}`, `CORINFO_HELP_{FLT,DBL}CMP_{LE,GE}`
(three-way compares with the libgcc `__le*f2`/`__ge*f2` unordered
conventions, so every ordered and unordered IL comparison is one call),
`CORINFO_HELP_FLT2DBL`, `CORINFO_HELP_DBL2FLT`. Conversions between FP and
integers reuse the existing `DBL2LNG`/`DBL2ULNG`/`*_OVF`/`LNG2*`/`ULNG2*`
helpers. ilc binds the new helpers to the compiler-rt symbols. Value numbering
models them as the operations they implement (`VNFunc(GT_ADD)` and friends,
as `CORINFO_HELP_LMUL` on 32-bit targets; the cast model for FLT2DBL/DBL2FLT);
only the two three-way compares need VNFuncs of their own.

### 4. Code generation: FP types live in integer registers

The IR keeps `TYP_FLOAT`/`TYP_DOUBLE`. What changes under soft-float is the
*register class* of those two types: the `varTypeRegister` table maps them to
`VTR_INT`, set once per process (the first compilation claims the
configuration and publishes it; a later compilation requesting the other
mode fails, as `GlobalJitOptions::compFeatureHfa` does on armel). Almost the
whole backend already decides by register class - `ins_Load/Store/Copy`,
`inst_Mov`, the call return register, `genHomeRegisterParams`,
`genPutArgReg`, LSRA's `regType`, `ReturnTypeDesc::GetABIReturnReg` - so FP
values are allocated, spilled, moved and returned in integer registers with
no further changes. The handful of places that decide by `varTypeIsFloating`
instead are adjusted (4-byte integer load/store selection, LSRA's per-type
register sets, FP constant materialization, `compFloatingPointUsed`, and
`BITCAST(int <- float)`, which must sign-extend because the psABI leaves the
upper bits of a float in an integer register undefined).

The operations are expanded in global morph through the existing hooks:
arithmetic via `USE_HELPER_FOR_ARITH` (as `LMUL` on 32-bit), conversions via
`fgCastRequiresHelper`/`fgMorphCastIntoHelper` (as on x86), comparisons into
a compare helper plus an integer relop, negation into a sign-bit XOR,
`CKFINITE` into a `GT_BOUNDS_CHECK` on the exponent field with
`SCK_ARITH_EXCPN`. FP `Math` intrinsics are declined by type in
`impMathIntrinsic` and remain calls to the managed implementations. The
debug JIT asserts on any F/D opcode reaching the emitter when F is not in the
instruction set, so an unexpanded node fails on the method that produced it.

Size: ~450 lines in the JIT, all under `#ifdef TARGET_RISCV64` and
`compUseSoftFP`; ~230 lines of helper plumbing; the ABI/ilc part is ~60.

### 5. Testing

* `src/tests/JIT/Directed/softfloat`: bit-exact expectations for arithmetic
  rounding, NaN comparison semantics including the unordered branch forms,
  saturating and checked conversions for every integer width, conversions
  from every integer width, float <-> double, negation, remainder, values
  across call boundaries, and float-bits-as-int sign extension. The test is
  valid on every target; on a soft-float image it exercises the real
  compiler-rt helpers.
* A soft-float NativeAOT image runs on any rv64gc machine (the builtins are
  integer code), so the existing riscv64 test infrastructure can run the
  suite with `--targetarch riscv64-lp64 --instruction-set=-a,-c` without
  special hardware.
* Downstream: 19 generated tests (7k assertions, goldens from an independent
  implementation) and the Ethereum stateless-execution guest validated
  byte-for-byte against the execution-spec fixtures on the zkVM emulator.

## Open questions for the owners

1. Is an explicit soft-float ABI for riscv64 acceptable as a NativeAOT-only
   target (no VM, no R2R), and is `riscv64-lp64` the spelling you want?
2. The atomics fallback of #132204 is a property of the same target (a
   single-threaded, deterministic guest); should the target definition carry
   it, so that the `A`-less assembly is selected by the target rather than
   by `__riscv_atomic`?
3. `PerfMapAbiToken` has no value for the new ABI (mapped to `Default`).
4. libm: `Math.Sin` & co resolve to the toolchain's libm; a soft-float libm is
   the toolchain's responsibility (as musl's is today), not the runtime's.
