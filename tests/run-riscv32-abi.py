#!/usr/bin/env python3
"""Round-trip RV32 ilp32 boundary arguments through native and managed callees.

Needs BFLAT, AIRBENDER_LIB (manifest), AIRBENDER_CLI and clang on PATH.
"""
import os
import pathlib
import subprocess
import tempfile


def run(args):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, args))}\n{result.stdout}")
    return result.stdout


value = 0x1122334455667788
tail = 0x13579
cs = ["""using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)] public struct Wide { public long Value; }
[StructLayout(LayoutKind.Sequential)] public struct Pair { public int Low, High; }
public static class Program {
    [MethodImpl(MethodImplOptions.NoInlining)] static long Read(ref long value) => value;
    [DllImport("__Internal", EntryPoint="check_callbacks")] static extern int CheckCallbacks();
    [DllImport("__Internal", EntryPoint="finish")] static extern void Finish(int failures);
"""]
c = ["""typedef unsigned int u32;
typedef unsigned long long u64;
struct Wide { long long Value; };
struct Pair { int Low, High; };
extern void airbender_finish_success(const u32 *words);
extern void airbender_finish_error(u32 error);
void finish(int failures) {
    const u32 words[16] = {0x50415353};
    if (failures) airbender_finish_error(failures);
    airbender_finish_success(words);
}
"""]
checks_cs, checks_c = [], []
types = (
    ("long", "long long", "value", "Read(ref value)", str(value), f"{value}LL"),
    ("double", "double", "((union { double d; u64 u; }){.d=value}).u",
     "BitConverter.DoubleToInt64Bits(value)", f"BitConverter.Int64BitsToDouble({value})",
     f"((union {{ u64 u; double d; }}){{.u={value}ULL}}).d"),
    ("Wide", "struct Wide", "value.Value", "Read(ref value.Value)",
     f"new Wide {{ Value={value} }}", f"((struct Wide){{{value}LL}})"),
    ("Pair", "struct Pair", "((u64)(u32)value.High << 32) | (u32)value.Low",
     "((long)value.High << 32) | (uint)value.Low",
     "new Pair { Low=0x55667788, High=0x11223344 }", "((struct Pair){0x55667788,0x11223344})"),
)
for cs_type, c_type, c_expr, cs_expr, cs_value, c_value in types:
    for count in (6, 7, 8, 9):
        name = f"{cs_type}_{count}"
        prefix = ", ".join(f"int a{i}" for i in range(count))
        cs_args = f"{prefix}, {cs_type} value, int tail"
        c_args = f"{prefix}, {c_type} value, int tail"
        args = ", ".join(str(i + 1) for i in range(count))
        cs.append(f'[DllImport("__Internal", EntryPoint="native_{name}")] static extern long Native_{name}({cs_args});')
        cs.append(f'[UnmanagedCallersOnly(EntryPoint="managed_{name}")] public static long Managed_{name}({cs_args}) => ({cs_expr}) ^ tail;')
        c.append(f'u64 native_{name}({c_args}) {{ return ({c_expr}) ^ tail; }}')
        c.append(f'extern u64 managed_{name}({c_args});')
        checks_cs.append(f'if (Native_{name}({args}, {cs_value}, {tail}) != {value ^ tail}) failures++;')
        checks_c.append(f'failures += managed_{name}({args}, {c_value}, {tail}) != {value ^ tail}ULL;')
cs.append('public static void Main() { int failures = CheckCallbacks();\n' + '\n'.join(checks_cs) + '\nFinish(failures); } }')
c.append('int check_callbacks(void) { int failures=0;\n' + '\n'.join(checks_c) + '\nreturn failures; }')

with tempfile.TemporaryDirectory(prefix="rv32-abi-") as directory:
    work = pathlib.Path(directory)
    (work / "probe.cs").write_text('\n'.join(cs))
    (work / "probe.c").write_text('\n'.join(c))
    (work / "empty.hex").write_text("")
    run([os.environ.get("CC", "clang"), "--target=riscv32-unknown-elf", "-march=rv32im", "-mabi=ilp32",
         "-O2", "-ffunction-sections", "-fdata-sections", "-c", str(work / "probe.c"), "-o", str(work / "probe.o")])
    for optimization in ("-Ot", "-O0"):
        output = work / ("optimized" if optimization == "-Ot" else "unoptimized")
        run([os.environ["BFLAT"], "build", "--arch", "riscv32", "--os", "linux", "--stdlib", "dotnet",
             "--libc", "airbender", optimization, "--no-reflection", "--no-stacktrace-data", "--no-pie",
             "--no-pthread", "--no-globalization", "--extlib", os.environ["AIRBENDER_LIB"],
             f"--ldflags={work / 'probe.o'}", "-o", str(output), str(work / "probe.cs")])
        result = run([os.environ["AIRBENDER_CLI"], "run", "--bin", str(output) + ".bin", "--text", str(output) + ".text",
                      "--input-file", str(work / "empty.hex"), "--cycles", "100000000",
                      "--expected-results", str(0x50415353), *(["0"] * 15)])
        print(f"RV32 ABI {optimization}: {len(checks_cs) + len(checks_c)} native/managed cases passed")
