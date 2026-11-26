// SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
// SPDX-License-Identifier: MIT

using System;
using System.Runtime.CompilerServices;

internal static class Program
{
    private const long Value64 = -0x123456789abcdef;
    private const int Value32 = unchecked((int)0x89abcdef);

    private static readonly long[] Counts = [0, 5, 31, 32, 37, 63, 64, -1, 0xffffffffL, 0x100000025L, long.MinValue];

    // Computed on x64 with a stock JIT, so that the JIT under test is not its own oracle.
    private static readonly ulong[] ExpectedShiftLeft64 =
    [
        0xfedcba9876543211UL, 0xdb97530eca864220UL, 0x3b2a190880000000UL, 0x7654321100000000UL, 0xca86422000000000UL,
        0x8000000000000000UL, 0xfedcba9876543211UL, 0x8000000000000000UL, 0x8000000000000000UL, 0xca86422000000000UL,
        0xfedcba9876543211UL
    ];

    private static readonly ulong[] ExpectedShiftRightUnsigned64 =
    [
        0xfedcba9876543211UL, 0x7f6e5d4c3b2a190UL, 0x1fdb97530UL, 0xfedcba98UL, 0x7f6e5d4UL, 0x1UL,
        0xfedcba9876543211UL, 0x1UL, 0x1UL, 0x7f6e5d4UL, 0xfedcba9876543211UL
    ];

    private static readonly long[] ExpectedShiftRight64 =
    [
        -81985529216486895, -2562047788015216, -38177488, -19088744, -596524, -1, -81985529216486895, -1, -1, -596524,
        -81985529216486895
    ];

    private static readonly int[] ExpectedShiftLeft32 =
    [
        -1985229329, 897170912, -2147483648, -1985229329, 897170912, -2147483648, -1985229329, -2147483648,
        -2147483648, 897170912, -1985229329
    ];

    private static readonly uint[] ExpectedShiftRightUnsigned32 =
    [
        0x89abcdefU, 0x44d5e6fU, 0x1U, 0x89abcdefU, 0x44d5e6fU, 0x1U, 0x89abcdefU, 0x1U, 0x1U, 0x44d5e6fU, 0x89abcdefU
    ];

    private static readonly int[] ExpectedShiftRight32 =
    [
        -1985229329, -62038417, -1, -1985229329, -62038417, -1, -1985229329, -1, -1, -62038417, -1985229329
    ];

    private static readonly long[] ExpectedShiftAndUseCount =
    [
        -81985529216486895, -2562047788015211, -38177457, -19088712, -596487, 62, -81985529216486831, -2, -2, -596487,
        -81985529216486895
    ];

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static ulong ShiftLeft64(ulong value, long count) => value << unchecked((int)count);

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static ulong ShiftRightUnsigned64(ulong value, long count) => value >> unchecked((int)count);

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static long ShiftRight64(long value, long count) => value >> unchecked((int)count);

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static int ShiftLeft32(int value, long count) => value << unchecked((int)count);

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static uint ShiftRightUnsigned32(uint value, long count) => value >> unchecked((int)count);

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static int ShiftRight32(int value, long count) => value >> unchecked((int)count);

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
        for (int i = 0; i < Counts.Length; i++)
        {
            long count = Counts[i];
            if (ShiftLeft64(unchecked((ulong)Value64), count) != ExpectedShiftLeft64[i] ||
                ShiftRightUnsigned64(unchecked((ulong)Value64), count) != ExpectedShiftRightUnsigned64[i] ||
                ShiftRight64(Value64, count) != ExpectedShiftRight64[i] ||
                ShiftLeft32(Value32, count) != ExpectedShiftLeft32[i] ||
                ShiftRightUnsigned32(unchecked((uint)Value32), count) != ExpectedShiftRightUnsigned32[i] ||
                ShiftRight32(Value32, count) != ExpectedShiftRight32[i] ||
                ShiftAndUseCount(Value64, count) != ExpectedShiftAndUseCount[i])
                return 1;
        }

        if (CheckedShift(Value64, -1) != -1)
            return 2;

        try
        {
            CheckedShift(Value64, 0xffffffffL);
            return 3;
        }
        catch (OverflowException)
        {
            return 0;
        }
    }
}
