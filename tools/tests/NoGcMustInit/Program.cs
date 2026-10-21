// SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
// SPDX-License-Identifier: MIT

using System;
using System.Runtime.CompilerServices;
using System.Threading;

internal static class Program
{
    // Larger than 32 bytes and not all GC slots: without the knob the JIT drops its explicit
    // zeroing and relies on the prolog's block init.
    private struct Pair
    {
        public object Obj;
        public long A, B, C, D;
    }

    private sealed class Box
    {
        public object Obj = null!;
        public long A, B, C, D;
    }

    private static long s_sink;

    // Leaves non-zero garbage where the next call's frame will be.
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void Dirty()
    {
        Span<long> junk = stackalloc long[512];
        junk.Fill(0x5A5A5A5A5A5A5A5A);
        s_sink += junk[0] + junk[511];
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static bool IsZero(ref Pair p) => p.Obj is null && (p.A | p.B | p.C | p.D) == 0;

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static bool IsNull(ref object o) => o is null;

    [SkipLocalsInit]
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static bool DefaultStruct()
    {
        Pair p = default;
        return IsZero(ref p);
    }

    [SkipLocalsInit]
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static bool NullReference()
    {
        object o = null!;
        return IsNull(ref o);
    }

    [SkipLocalsInit]
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static bool NewObject()
    {
        Box b = new();
        // Volatile reads keep the field loads observable without making the object escape.
        return Volatile.Read(ref b.Obj) is null &&
            (Volatile.Read(ref b.A) | Volatile.Read(ref b.B) |
             Volatile.Read(ref b.C) | Volatile.Read(ref b.D)) == 0;
    }

    private static int Main()
    {
        int failed = 0;

        Dirty();
        if (!DefaultStruct()) { Console.WriteLine("default(struct with GC refs) read garbage"); failed++; }
        Dirty();
        if (!NullReference()) { Console.WriteLine("null reference local read garbage"); failed++; }
        Dirty();
        if (!NewObject()) { Console.WriteLine("new object read garbage"); failed++; }

        if (failed != 0)
        {
            return 1;
        }

        Console.WriteLine("Zero-init regression passed.");
        return 0;
    }
}
