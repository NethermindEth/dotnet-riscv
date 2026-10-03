using System;
using System.Runtime.CompilerServices;

internal static class Program
{
    private static int Main()
    {
        Check(0, ulong.MaxValue, 0, 0);
        Check(1, ulong.MaxValue, 0, ulong.MaxValue);
        Check(ulong.MaxValue, ulong.MaxValue, ulong.MaxValue - 1, 1);
        Check(1UL << 63, 2, 1, 0);
        Check(1UL << 32, (1UL << 32) + 1, 1, 1UL << 32);
        Console.WriteLine("BigMul regression passed.");
        return 0;
    }

    // Force optimized compilation with nonconstant factors even when tiering is enabled.
    [MethodImpl(MethodImplOptions.NoInlining | MethodImplOptions.AggressiveOptimization)]
    private static void Check(ulong a, ulong b, ulong expectedHigh, ulong expectedLow)
    {
        ulong high = Math.BigMul(a, b, out ulong low);
        if (high != expectedHigh || low != expectedLow)
        {
            throw new Exception($"BigMul({a:X16}, {b:X16}): {high:X16}:{low:X16}, expected {expectedHigh:X16}:{expectedLow:X16}");
        }
    }
}
