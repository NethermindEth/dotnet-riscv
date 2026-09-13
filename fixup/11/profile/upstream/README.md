# `upstream` profile — patches staged for dotnet/runtime

This profile is **not** a build configuration for the zkVM SDK. It is the staging
area for changes we intend to submit to dotnet/runtime, kept in a form that can be
applied and built on its own.

Apply it with:

```sh
./patch_runtime.sh upstream
```

Unlike `minimal` and `perf`, this profile is standalone: it does not include
`minimal`. That is the point — an upstream PR has to stand on its own, so if the
subset here does not apply and build against a clean VMR runtime, it is not ready.

## CI

The **Build .NET SDK** workflow takes `profile` (`minimal` / `perf` / `upstream`)
and `soft_float_abi`. Two runs are worth doing before proposing anything here:

| `profile` | `soft_float_abi` | what it proves |
|---|---|---|
| `upstream` | **false** | the patches change nothing for an ordinary rv64gc/lp64d target — the claim every one of these commits makes in its message. This is the run that matters here. |
| `minimal` | **true** | the ISA/ABI machinery actually builds a soft-float runtime, with `check_lp64.sh` gating the result |

`upstream` + `soft_float_abi=true` does **not** work, by construction: the
runtime's `.S` sources still contain unguarded `fsd`/`fld` and `amo*`, and the
patches that gate them on `__riscv_flen` / `__riscv_atomic` (`minimal/11` and
`minimal/14`) are not here — they are still under review on
dotnet/runtime#132204. The assembler rejects those files under `-march=rv64im`.
So the soft-float leg has to run on `minimal`, and the `upstream` profile is
for proving the no-op claim.

`soft_float_abi` also selects the rootfs: `true` applies the custom lp64 Alpine
(`patch_alpine.sh`), `false` uses the stock userspace. The `upstream` profile
only exists for .NET 11, so the VMR branch has to be an 11.x one.

A green run of the first is what moves a patch from "applies clean" to
run-verified.

## Bar for inclusion

A patch goes in here only when **all** of the following hold. Anything short of
that stays in `minimal`/`perf`.

1. **Upstream-shaped.** It exists as a clean commit series on an `upstream/<topic>`
   branch in the `runtime.11` working repo, with the commit messages we would
   actually submit — not as a squashed downstream fixup.
2. **Nothing zkVM- or Nethermind-specific.** No downstream knobs, no assumptions
   about the guest environment. If the change only makes sense for our target, it
   is not an upstream candidate.
3. **Stands alone.** Applies to the stated base commit and builds without any
   other patch from this repo.
4. **Run-verified**, not just build-verified. Someone executed the code and
   recorded the result; "compiles clean" is not enough.
5. **Defaults unchanged.** A configuration that does not opt in behaves exactly as
   it does upstream today.

## Contents

| Patch | Origin branch (`runtime.11`) | Base | Status |
|---|---|---|---|
| `01_riscv64_isa_sets_fdca.patch` | `upstream/riscv64-isa-sets` (`ac0a0ffe`) | `e1d442a6` | applies clean; result is byte-identical to the branch tip |
| `02_riscv64_gate_fp_compressed_emission.patch` | `upstream/riscv64-isa-sets` (`22ce851d`) | `e1d442a6` | same |
| `03_riscv64_configurable_march_abi.patch` | `upstream/riscv64-build-abi` (`497d9430`) | `e1d442a6` | applies clean; mechanism verified with cmake, **not yet built** |
| `04_riscv64_toolchain_march_abi.patch` | `upstream/riscv64-build-abi` (`18ee45bf`) | `e1d442a6` | same |
| `05_riscv64_libunwind_no_fp.patch` | `upstream/riscv64-build-abi` (`e3a26041`) | `e1d442a6` | applies clean; headers and `dwarf_getfp`/`dwarf_putfp` compile clean for `rv64im`, `rv64gc` and `rv64imf` under `-Wall -Wextra -Werror`; **not yet built in tree** |

Patches 03-05 are what replaced the `tools/clang` wrapper; see below. They are
duplicated as `minimal/31`-`33`, because the downstream build runs the `minimal`
profile and needs them too — edit the branch and re-export both.

### Building for a soft-float RISC-V target without a compiler wrapper

Two variables, and the ISA is the same everywhere:

```sh
build.sh --arch riscv64 --os linux-musl \
    -cmakeargs "-DCLR_CMAKE_RISCV64_MABI=lp64" \
    -cmakeargs "-DCLR_CMAKE_RISCV64_MARCH=rv64im"
```

* `MABI` applies to everything, including cmake's own probes, so the whole build
  agrees with an lp64 sysroot and lld never sees two float ABIs.
* `MARCH` is the instruction set for the whole native build. `rv64im` is possible
  because patch 05 teaches the savannah libunwind that the PAL uses to build
  with `__riscv_flen == 0`; before it, that component was the one thing that
  forced a wider ISA on everything outside the NativeAOT tree.

There is deliberately no second, narrower ISA for the NativeAOT subtree any
more: one ISA for the whole build is simpler to reason about, and there is no
component left that needs the wider one.

Anything else the old wrapper injected (`-mno-relax`, `-fno-jump-tables`, and
so on) goes through the pre-existing `CLR_ADDITIONAL_COMPILER_OPTIONS` and
`CLR_ADDITIONAL_LINKER_FLAGS`. Note that `$(CMakeArgs)` is split on `;` by
MSBuild in `src/coreclr/runtime.proj`, so a list value has to escape its
separators as `%3B`.

Both were exported with `git format-patch`, so each carries the commit message it
would be submitted with. Re-export after any change to the branch rather than
editing the patch files by hand:

```sh
git -C <your runtime.11 checkout> format-patch --no-signature --zero-commit --no-numbered \
    -o <tmp> e1d442a6..upstream/riscv64-isa-sets
```

## Deliberately not here yet

* **Soft-float series (`minimal` 26–29).** Fully validated downstream — CI green on
  `fa68384`, release `v11.0.0.x17-sf`, 21/21 tests under a checked JIT, guest 8/8
  EEST golden pairs — so it clears bars 2–5. It fails bar 1: it has not been
  reshaped onto `upstream/riscv64-isa-sets` as an upstream commit series, and it
  would conflict with `01`/`02` if dropped in as-is (both touch
  `jiteeversionguid.h` and `InstructionSetHelpers.cs`). It is also gated on the
  design issue (`softfloat_design_issue.md`) reaching a conclusion first.
* **`jit-release-inline-knobs`.** Staged separately in `upstream/` at the repo root.
  Its own README says it is not run-verified, so it fails bar 4.
* **ISA-mode `.S` patches (`minimal` 11/14/15).** Open review feedback on
  dotnet/runtime#132204.
* **Patch 30 (single-threaded runtime flavor).** Decision taken 2026-08-27 not to
  submit it.
