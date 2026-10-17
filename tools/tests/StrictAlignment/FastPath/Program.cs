// SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
// SPDX-License-Identifier: MIT

using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

// Exercises the alignment-checked accesses of JitRiscV64StrictAlign at every misalignment: through a
// byref parameter plus constant offsets that are multiples of the access size (the folded base+offset
// form), plus offsets that are not, and through stackalloc'd space; then several accesses through one
// base, whose alignment test is shared (the base reassigned between them, offsets that change the
// alignment, mixed sizes, pointers and span fields). Each access is checked against the value assembled
// from single bytes. Success exits with code 0, a mismatch with the case number.
static unsafe class Program
{
    static readonly byte[] Buffer = new byte[160];
    static int _case;

    static int Main()
    {
        for (int i = 0; i < Buffer.Length; i++)
            Buffer[i] = (byte)(i * 37 + 11);

        for (int misalignment = 0; misalignment < 8; misalignment++)
        {
            ref byte p = ref Buffer[64 + misalignment];
            Check(Load64(ref p), Expected(64 + misalignment + 16, 8));
            Check(Load64Back(ref p), Expected(64 + misalignment - 8, 8));
            Check(Load64Odd(ref p), Expected(64 + misalignment + 3, 8));
            Check(Load32(ref p), Expected(64 + misalignment + 12, 4));
            Check(Load32Sign(ref p), (ulong)(long)(int)Expected(64 + misalignment + 4, 4));
            Check(Load16(ref p), Expected(64 + misalignment + 6, 2));
            Check(Load16Sign(ref p), (ulong)(long)(short)Expected(64 + misalignment + 2, 2));
            Check(LoadAs64(ref p), Expected(64 + misalignment + 24, 8));
        }

        for (int misalignment = 0; misalignment < 8; misalignment++)
        {
            ref byte p = ref Buffer[64 + misalignment];
            Store64(ref p, 0x0123456789ABCDEF);
            Check(Expected(64 + misalignment + 8, 8), 0x0123456789ABCDEF);
            Store64Back(ref p, 0x1122334455667788);
            Check(Expected(64 + misalignment - 16, 8), 0x1122334455667788);
            Store32(ref p, 0xDEADBEEF);
            Check(Expected(64 + misalignment + 20, 4), 0xDEADBEEF);
            Store16(ref p, 0xCAFE);
            Check(Expected(64 + misalignment + 30, 2), 0xCAFE);
            StoreAs64(ref p, 0x8877665544332211);
            Check(Expected(64 + misalignment + 32, 8), 0x8877665544332211);
        }

        Check(StackAllocated(9), 0x0909090909090909UL * 9 + 36);

        for (int misalignment = 0; misalignment < 8; misalignment++)
        {
            int at = 64 + misalignment;
            ref byte p = ref Buffer[at];
            Check(Words(ref p), Expected(at, 8) + Expected(at + 8, 8) + Expected(at + 16, 8) + Expected(at + 24, 8));
            Check(MixedSizes(ref p),
                Expected(at + 2, 2) ^ Expected(at + 8, 8) ^ Expected(at + 4, 4) ^ Expected(at + 16, 8));
            Check(OddOffsets(ref p),
                Expected(at, 8) + Expected(at + 4, 8) + Expected(at + 16, 8) + Expected(at + 3, 4));
            for (int step = 0; step < 8; step++)
            {
                Check(Reassigned(ref p, step),
                    Expected(at, 8) + Expected(at + 8, 8) + Expected(at + step, 8) + Expected(at + step + 8, 8));
                ulong bumped = 0;
                for (int i = 0; i < 4; i++)
                    bumped += Expected(at + i * step, 8) ^ Expected(at + i * step + 8, 4);
                Check(Bumped(ref p, step, 4), bumped);
                Check(SpanReassigned(Buffer.AsSpan(at, 16), Buffer.AsSpan(at + step, 16)),
                    Expected(at, 8) - Expected(at + 8, 8) + Expected(at + step, 8) - Expected(at + step + 8, 8));
            }
            fixed (byte* buffer = Buffer)
                Check(PointerWords(buffer + at), Expected(at, 8) * 3 + Expected(at + 8, 8) * 5 + Expected(at + 16, 4));
            Check(SpanWords(Buffer.AsSpan(at, 24)), Expected(at, 8) - Expected(at + 8, 8) - Expected(at + 16, 8));
        }

        for (int misalignment = 0; misalignment < 8; misalignment++)
        {
            int at = 64 + misalignment;
            StoreWords(ref Buffer[at], 0x0102030405060708);
            Check(Expected(at, 8), 0x0102030405060708);
            Check(Expected(at + 8, 8), 0x0102030405060709);
            Check(Expected(at + 16, 4), 0x0506070A);
            Check(Expected(at + 20, 2), 0x070B);
        }
        return 0;
    }

    static ulong Expected(int index, int size)
    {
        ulong value = 0;
        for (int i = size - 1; i >= 0; i--)
            value = (value << 8) | Buffer[index + i];
        return value;
    }

    static void Check(ulong actual, ulong expected)
    {
        _case++;
        if (actual != expected)
            Environment.Exit(_case);
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Load64(ref byte p) => Unsafe.ReadUnaligned<ulong>(ref Unsafe.Add(ref p, 16));

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Load64Back(ref byte p) => Unsafe.ReadUnaligned<ulong>(ref Unsafe.Subtract(ref p, 8));

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Load64Odd(ref byte p) => Unsafe.ReadUnaligned<ulong>(ref Unsafe.Add(ref p, 3));

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Load32(ref byte p) => Unsafe.ReadUnaligned<uint>(ref Unsafe.Add(ref p, 12));

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Load32Sign(ref byte p) => (ulong)(long)Unsafe.ReadUnaligned<int>(ref Unsafe.Add(ref p, 4));

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Load16(ref byte p) => Unsafe.ReadUnaligned<ushort>(ref Unsafe.Add(ref p, 6));

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Load16Sign(ref byte p) => (ulong)(long)Unsafe.ReadUnaligned<short>(ref Unsafe.Add(ref p, 2));

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong LoadAs64(ref byte p) => Unsafe.As<byte, ulong>(ref Unsafe.Add(ref p, 24));

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void Store64(ref byte p, ulong value) => Unsafe.WriteUnaligned(ref Unsafe.Add(ref p, 8), value);

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void Store64Back(ref byte p, ulong value) => Unsafe.WriteUnaligned(ref Unsafe.Subtract(ref p, 16), value);

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void Store32(ref byte p, uint value) => Unsafe.WriteUnaligned(ref Unsafe.Add(ref p, 20), value);

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void Store16(ref byte p, ushort value) => Unsafe.WriteUnaligned(ref Unsafe.Add(ref p, 30), value);

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void StoreAs64(ref byte p, ulong value) => Unsafe.As<byte, ulong>(ref Unsafe.Add(ref p, 32)) = value;

    static ulong Read64(ref byte p, int offset) => Unsafe.ReadUnaligned<ulong>(ref Unsafe.Add(ref p, offset));

    static ulong Read32(ref byte p, int offset) => Unsafe.ReadUnaligned<uint>(ref Unsafe.Add(ref p, offset));

    static ulong Read16(ref byte p, int offset) => Unsafe.ReadUnaligned<ushort>(ref Unsafe.Add(ref p, offset));

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Words(ref byte p) => Read64(ref p, 0) + Read64(ref p, 8) + Read64(ref p, 16) + Read64(ref p, 24);

    // The narrow accesses come first; the shared test is for the widest one.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong MixedSizes(ref byte p) => Read16(ref p, 2) ^ Read64(ref p, 8) ^ Read32(ref p, 4) ^ Read64(ref p, 16);

    // p + 4 and p + 3 have another alignment than p, so their accesses keep their own test.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong OddOffsets(ref byte p) => Read64(ref p, 0) + Read64(ref p, 4) + Read64(ref p, 16) + Read32(ref p, 3);

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Reassigned(ref byte p, int step)
    {
        ref byte q = ref p;
        ulong sum = Read64(ref q, 0) + Read64(ref q, 8);
        q = ref Unsafe.Add(ref q, step);
        return sum + Read64(ref q, 0) + Read64(ref q, 8);
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Bumped(ref byte p, int step, int count)
    {
        ref byte q = ref p;
        ulong sum = 0;
        for (int i = 0; i < count; i++)
        {
            sum += Read64(ref q, 0) ^ Read32(ref q, 8);
            q = ref Unsafe.Add(ref q, step);
        }
        return sum;
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong PointerWords(byte* p) => *(ulong*)p * 3 + *(ulong*)(p + 8) * 5 + *(uint*)(p + 16);

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong SpanWords(ReadOnlySpan<byte> span)
    {
        ref byte p = ref MemoryMarshal.GetReference(span);
        return Read64(ref p, 0) - Read64(ref p, 8) - Read64(ref p, 16);
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong SpanReassigned(Span<byte> span, Span<byte> other)
    {
        ulong sum = Read64(ref MemoryMarshal.GetReference(span), 0) - Read64(ref MemoryMarshal.GetReference(span), 8);
        span = other;
        return sum + Read64(ref MemoryMarshal.GetReference(span), 0) - Read64(ref MemoryMarshal.GetReference(span), 8);
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void StoreWords(ref byte p, ulong value)
    {
        Unsafe.WriteUnaligned(ref p, value);
        Unsafe.WriteUnaligned(ref Unsafe.Add(ref p, 8), value + 1);
        Unsafe.WriteUnaligned(ref Unsafe.Add(ref p, 16), (uint)value + 2);
        Unsafe.WriteUnaligned(ref Unsafe.Add(ref p, 20), (ushort)(value + 3));
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong StackAllocated(int count)
    {
        ulong* words = stackalloc ulong[count];
        for (int i = 0; i < count; i++)
            words[i] = 0x0909090909090909UL + (ulong)i;
        ulong sum = 0;
        for (int i = 0; i < count; i++)
            sum += words[i];
        return sum;
    }
}
