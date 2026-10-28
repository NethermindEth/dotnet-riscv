# dotnet-riscv

[![Build .NET SDK](https://github.com/nethermindeth/dotnet-riscv/actions/workflows/build.yml/badge.svg)](https://github.com/nethermindeth/dotnet-riscv/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/nethermindeth/dotnet-riscv?include_prereleases)](https://github.com/nethermindeth/dotnet-riscv/releases)
[![Platform](https://img.shields.io/badge/platform-RISC--V-blue.svg)](https://riscv.org/)
[![.NET](https://img.shields.io/badge/.NET-10.0-512BD4.svg)](https://dotnet.microsoft.com/)

This project is a pipeline for building RISC-V .NET runtime for [Nethermind client](https://github.com/nethermindeth/nethermind).

## Why is it needed?

[Nethermind client](https://github.com/nethermindeth/nethermind)'s [Stateless Executor](https://github.com/NethermindEth/nethermind/tree/master/src/Nethermind/Nethermind.Stateless.Executor) has to be compiled natively for the RISC-V platform. To do this, runtime requires several patches, namely for:
 - bflat runtime support.
 - support for custom Alpine images.
 - disabling of compressed instructions.
 - disabling of floating point support (both for runtime binaries and inside the code generator).
 - removing switch jump tables.

## How to build?
To build the project, please check the available GitHub Actions for the main
branch and run **Build .NET SDK**:

 - Choose **dotnet VMR fork name**=`dotnet`
 - Choose **dotnet VMR branch name**=`release/10.0.100`
 - Tick **Publish release**

## The linux-x64 target of bflat

bflat also builds ordinary linux-x64 programs. The `runtime-x64` job makes
the three release assets for that target:

- `bflat-compiler-native-x64-linux-glibc-x64.zip`: the x64 JIT
  (`libclrjit_unix_x64_x64.so`) that ILCompiler loads;
- `bflat-libs-linux-glibc-x64.zip`: the NativeAOT runtime, CoreLib and the
  framework libraries;
- `libs-linux-glibc-x64.zip`: the glibc and gcc files of the link, from the
  x64 rootfs of the dotnet/runtime cross-build container.

Microsoft's x64 packages cannot be used: the fixups change the JIT/EE
interface (`bump_jitee_guid.sh`), so the JIT and CoreLib must be built from
the same sources as the ILCompiler of `bflat.compiler.10.0.0.nupkg`. The job
clones dotnet/runtime at the commit that the VMR pins and applies the same
profile (`runtime_tests.sh source`), then builds and packs the target
(`10_build_runtime_x64.sh`, `11_pack_x64.sh`).

## Signed releases

The release has two more assets: `bflat-signature.sha256`, the SHA-256 of
each other asset, and `bflat-signature.sha256.sig`, its signature. The
build job writes the list (`tools/sign_package.py list-files`). The sign
job, the reusable workflow `sign.yml` of bflat-riscv64, signs it with the
secret `BFLAT_SIGNING_KEY`; it is the only job that has the key, and it runs
no build. The release job checks the assets against the list and the
signature (`tools/sign_package.py check-files`, with the variable
`BFLAT_SIGNING_PUBLIC_KEY`) before it makes the release. The bflat build
checks the assets that it downloads against them (`docs/signing.md` in
bflat-riscv64). `tools/sign_package.py` is a copy of the script in
bflat-riscv64; keep it the same.

## The riscv32 target

`RISCV32=1 ./patch_runtime.sh upstream-perf` adds the RV32IM ilp32 target
(`fixup/<major>/riscv32`) on top of the `upstream-perf` profile. CI does not
build it yet.

The riscv32 runtime builds against a static sysroot, its `CROSS_ROOTFS`, made
with clang and the LLVM tools:

```bash
./build_musl_rv32im.sh <sysroot>       # musl 1.2.5 without lr/sc
./build_libatomic_rv32im.sh <sysroot>  # soft __atomic_* for a single hart
./build_builtins_rv32im.sh <sysroot>   # compiler-rt builtins at the clang's tag
```

Each script fails if its output carries a compressed or atomic instruction.

## License

All third-party patches belong to their corresponding authors. Nethermind's own patches and scripts are licensed under MIT license.
