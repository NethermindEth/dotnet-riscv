# dotnet-riscv

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
 - Choose **dotnet VMR branch name**=`release/10.0.1xx`
 - Tick **Publish release**

## License

All third-party patches belong to their corresponding authors. Nethermind's own patches and scripts are licensed under MIT license.
