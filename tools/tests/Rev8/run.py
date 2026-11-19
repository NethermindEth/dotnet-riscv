#!/usr/bin/env python3
"""Check the RV32-only rev8 override with a bflat SDK that includes both RISC-V targets."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

source = """using System.Buffers.Binary;
using System.Runtime.CompilerServices;

class Program
{
    [MethodImpl(MethodImplOptions.NoInlining)]
    static int SwapWord(int input) => BinaryPrimitives.ReverseEndianness(input);

    static int Main(string[] args) => SwapWord(args.Length);
}
"""

with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    (work / "probe.cs").write_text(source)
    for arch in ("riscv32", "riscv64"):
        for enabled in (0, 1):
            subprocess.run([os.environ.get("BFLAT", "bflat"), "build", "--arch", arch, "--os", "linux",
                            "--libc", "musl", "--stdlib", "dotnet", "-c", "-Ot", "--no-reflection",
                            "--codegenopt", f"JitZkRev8={enabled}", "-o", "probe.o", "probe.cs"],
                           cwd=work, check=True)
            asm = subprocess.check_output([os.environ.get("OBJDUMP", "llvm-objdump"), "-d", "--mattr=+zbb",
                                           "--no-show-raw-insn", "probe.o"], cwd=work, text=True)
            body = re.search(r"(?m)^[0-9a-f]+ <[^>]*SwapWord[^>]*>:\n((?:[^\n]+\n)+)", asm)
            if body is None:
                raise RuntimeError(f"{arch}: SwapWord missing from object")
            expected = arch == "riscv32" and enabled == 1
            if bool(re.search(r"\brev8\b", body[1])) != expected:
                raise RuntimeError(f"{arch}, JitZkRev8={enabled}: unexpected instructions\n{body[1]}")
            print(f"{arch}, JitZkRev8={enabled}: passed", flush=True)
