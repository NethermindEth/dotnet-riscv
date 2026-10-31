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

bflat also builds RV32IM ilp32 guests for the ZKsync Airbender zkVM (no C, A,
F or D extensions, no fences). With the `upstream-perf` profile, **Build .NET
SDK** applies the riscv32 fixups (`fixup/<major>/riscv32`, `RISCV32=1` of
`patch_runtime.sh`) to every job, which gives the ILCompiler of
`bflat.compiler.10.0.0.nupkg` the RiscV32 target, and the `runtime-riscv32`
job makes the four release assets of the target:

- `bflat-compiler-native-riscv32-linux-glibc-x64.zip`: the riscv32 cross JIT
  (`libclrjit_unix_riscv32_x64.so`) that ILCompiler loads;
- `bflat-libs-linux-musl-riscv32.zip`: the NativeAOT runtime, CoreLib, the
  static native libraries (`libSystem.Native.a`, compression, ...) and the
  framework libraries;
- `libs-linux-musl-riscv32.zip`: the files of the sysroot that the link
  needs: musl's crt objects and libraries, the soft `libatomic.a` and the
  compiler-rt builtins;
- `crossrootfs-musl-riscv32.tar.xz`: the whole rv32im sysroot, headers
  included, for the C code that bflat builds.

The **riscv32** box (on by default) turns this off; other profiles have no
riscv32. With **skip SDK** the job runs alone, without a release. As for the
linux-x64 target, the job clones dotnet/runtime at the commit that the VMR
pins, with the same fixups and JIT/EE GUID, so the JIT and CoreLib agree with
the ILCompiler of the package; the riscv32 fixups change the JIT/EE contract,
so they have a GUID of their own (`bump_jitee_guid.sh`). riscv32 builds only
the NativeAOT runtime; the framework libraries are the x64 build of the same
sources, as their IL does not depend on the architecture outside CoreLib.
Locally:

```bash
RISCV32=1 ./runtime_tests.sh source dotnet <vmr branch> upstream-perf
./12_build_runtime_riscv32.sh
./13_pack_riscv32.sh
```

The riscv32 runtime builds against a static sysroot, its `CROSS_ROOTFS`, made
with clang and the LLVM tools, without linker relaxation (`ld -r` would keep
padding that can leave code on a 2-byte boundary):

```bash
./build_musl_rv32im.sh <sysroot>       # musl 1.2.5 without lr/sc and fences
./build_libatomic_rv32im.sh <sysroot>  # soft __atomic_* for a single hart
./build_builtins_rv32im.sh <sysroot>   # compiler-rt builtins at the clang's tag
./install_linux_headers_rv32.sh <sysroot>  # the Linux UAPI headers
./build_libcxx_headers_rv32.sh <sysroot>   # the libc++ headers at the clang's tag
```

Each script fails if its output carries a compressed or atomic instruction.
`13_pack_riscv32.sh` fails on an asset object that is not ilp32 or claims the
C extension (`check_ilp32.sh`, the counterpart of `check_lp64.sh`), or that
carries a compressed, atomic or fence instruction (`tools/isa_scan.py`). The
run job checks that the ILCompiler of the package has the RiscV32 target.

`python3 tests/run-riscv32-abi.py` checks scalar and aggregate arguments at the
register/stack boundary in both directions between native and managed code,
with and without optimization, on the Airbender simulator. Set `BFLAT` to the
bflat built against this target, `AIRBENDER_LIB` to the libairbender manifest
and `AIRBENDER_CLI` to the Airbender CLI; clang must support RV32IM/ilp32
(`CC` overrides it).

## License

All third-party patches belong to their corresponding authors. Nethermind's own patches and scripts are licensed under MIT license.
