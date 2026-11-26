// SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
// SPDX-License-Identifier: MIT

using System;
using System.Runtime.CompilerServices;

internal static class Program
{
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static ulong Shift64(ulong value, long count) => value >> unchecked((int)count);

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static int Shift32(int value, long count) => value << unchecked((int)count);

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static long CheckedShift(long value, long count) => value >> checked((int)count);

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static long ShiftAndUseCount(long value, long count)
    {
        int narrowed = unchecked((int)count);
        return (value >> narrowed) + narrowed;
    }

    private static int Main()
    {
        const long value = -0x123456789abcdef;
        foreach (long count in new long[] { 0, 31, 32, 63, 64, -1, 0xffffffffL, 0x100000020L, long.MinValue })
        {
            int lowBits = (int)(count & 63);
            if (Shift64(unchecked((ulong)value), count) != (unchecked((ulong)value) >> lowBits) ||
                Shift32(123, count) != (123 << (lowBits & 31)) ||
                ShiftAndUseCount(value, count) != (value >> lowBits) + unchecked((int)count))
                return 1;
        }

        if (CheckedShift(value, -1) != (value >> 63))
            return 2;

        try
        {
            CheckedShift(value, 0xffffffffL);
            return 3;
        }
        catch (OverflowException)
        {
            return 0;
        }
    }
}
