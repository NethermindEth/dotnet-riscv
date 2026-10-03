# BigMul regression

Checks both halves of unsigned multiplication with nonconstant inputs and forces
optimized compilation. On RISC-V, the new intrinsic must pass the binary
`gtSetEvalOrder` switch in a Checked/Debug JIT without asserting.

Build the portable test assembly:

```sh
dotnet build tools/tests/BigMul/BigMul.csproj -c Release -o /tmp/bigmul-regression
```

On a RISC-V machine, run it using a Core_Root containing a Checked/Debug JIT and
CoreLib built with the `upstream-perf` patches through `perf-48`:

```sh
DOTNET_ReadyToRun=0 DOTNET_TieredCompilation=0 /path/to/Core_Root/corerun /tmp/bigmul-regression/BigMul.dll
```

Success prints `BigMul regression passed.` and exits with code 0. Running the
same assembly on x64 checks the expected products but does not exercise the
RISC-V importer or its evaluation-order assertion.
