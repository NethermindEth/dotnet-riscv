# dotnet-riscv

[![Build .NET SDK](https://github.com/nethermindeth/dotnet-riscv/actions/workflows/build.yml/badge.svg)](https://github.com/nethermindeth/dotnet-riscv/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/nethermindeth/dotnet-riscv?include_prereleases)](https://github.com/nethermindeth/dotnet-riscv/releases)
[![Platform](https://img.shields.io/badge/platform-RISC--V-blue.svg)](https://riscv.org/)
[![.NET](https://img.shields.io/badge/.NET-10.0-512BD4.svg)](https://dotnet.microsoft.com/)

This project is a pipeline for building RISC-V .NET runtime for [Nethermind client](https://github.com/nethermindeth/nethermind).

## Why is it needed?

[Nethermind client](https://github.com/nethermindeth/nethermind)'s [Stateless Executor](https://github.com/NethermindEth/nethermind/tree/tanishq/feature/stateless_execv2/tools/StatelessExecution) has to be compiled natively for the RISC-V platform. To do this, runtime requires several patches, namely for:
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

## License

All third-party patches belong to their corresponding authors. Nethermind's own patches and scripts are licensed under MIT license.
