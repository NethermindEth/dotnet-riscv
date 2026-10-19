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
    static ulong _sink;

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

        for (int misalignment = 0; misalignment < 8; misalignment++)
        {
            int at = 64 + misalignment;
            ref byte p = ref Buffer[at];
            ulong chain = Expected(at, 8);
            Check(Chain(ref p, 0), chain);
            chain += Expected(at + 8, 8) * 3;
            Check(Chain(ref p, 1), chain);
            chain ^= Expected(at + 16, 8);
            Check(Chain(ref p, 2), chain);
            Check(Chain(ref p, 3), chain + Expected(at + 24, 8));
            ulong narrow = Expected(at + 2, 2);
            Check(NarrowFirst(ref p, 0), narrow);
            narrow += Expected(at + 4, 4);
            Check(NarrowFirst(ref p, 1), narrow);
            Check(NarrowFirst(ref p, 2), narrow + Expected(at + 8, 8));
            Check(Diamond(ref p, true), (Expected(at, 8) + Expected(at + 8, 8)) ^ Expected(at + 16, 8));
            Check(Diamond(ref p, false), (Expected(at, 8) - Expected(at + 12, 4)) ^ Expected(at + 16, 8));
            ulong loop = 0;
            for (int i = 0; i < 3; i++)
            {
                loop += Expected(at, 8);
                if ((loop & 1) != 0)
                    loop ^= Expected(at + 8, 8);
                loop += Expected(at + 16, 4);
            }
            Check(LoopBack(ref p, 3), loop);
            Check(_sink, loop);
            for (int step = 0; step < 8; step++)
            {
                ulong moved = Expected(at, 8);
                Check(ReassignedBetweenBlocks(ref p, step, 0), moved);
                moved += Expected(at + step + 8, 8);
                Check(ReassignedBetweenBlocks(ref p, step, 1), moved);
                Check(ReassignedBetweenBlocks(ref p, step, 2), moved + Expected(at + step + 16, 8));

                int other = 96 + step;
                ulong both = Expected(at, 8) + Expected(other, 8);
                Check(OtherBaseMoved(ref p, ref Buffer[other], step, 0), both);
                both += Expected(at + 8, 8) ^ Expected(other + step + 8, 8);
                Check(OtherBaseMoved(ref p, ref Buffer[other], step, 1), both);
                both += Expected(at + 16, 8) - Expected(other + step + 16, 8);
                Check(OtherBaseMoved(ref p, ref Buffer[other], step, 2), both);
                Check(OtherBaseMoved(ref p, ref Buffer[other], step, 3), both * 3);
            }

            // b equals a or has one limb one more or one less, so the compare exits at every limb.
            ref Limbs a = ref Unsafe.As<byte, Limbs>(ref p);
            for (int limb = 0; limb <= 4; limb++)
            {
                for (int delta = -1; delta <= 1; delta += 2)
                {
                    Limbs b = ExpectedLimbs(at);
                    if (limb < 4)
                        Unsafe.Add(ref b.U0, limb) += (ulong)(long)delta;
                    Check(LessThan(in a, in b), (limb < 4) && (delta > 0) ? 1UL : 0UL);
                    Check(LessThan(in b, in a), (limb < 4) && (delta < 0) ? 1UL : 0UL);
                }
            }
        }

        for (int misalignment = 0; misalignment < 8; misalignment++)
        {
            int at = 64 + misalignment;
            for (int exit = 0; exit < 3; exit++)
            {
                Array.Clear(Buffer, at, 24);
                StoreChain(ref Buffer[at], 0x1112131415161718, exit);
                Check(Expected(at, 8), 0x1112131415161718);
                Check(Expected(at + 8, 8), exit >= 1 ? 0x1112131415161719UL : 0);
                Check(Expected(at + 16, 4), exit >= 2 ? 0x1516171AUL : 0);
            }
        }
        return 0;
    }

    struct Limbs
    {
        public ulong U0, U1, U2, U3;
    }

    static Limbs ExpectedLimbs(int at) =>
        new Limbs { U0 = Expected(at, 8), U1 = Expected(at + 8, 8), U2 = Expected(at + 16, 8), U3 = Expected(at + 24, 8) };

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
        // SP1 halts with an 8-bit exit code: a multiple of 256 would read as success.
        if (actual != expected)
            Environment.Exit(1 + (_case - 1) % 255);
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

    // Each word is read in its own block: the branches between them end the blocks, and every one of them
    // can leave the method early.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Chain(ref byte p, int exit)
    {
        ulong sum = Read64(ref p, 0);
        if (exit == 0)
            return sum;
        sum += Read64(ref p, 8) * 3;
        if (exit == 1)
            return sum;
        sum ^= Read64(ref p, 16);
        if (exit == 2)
            return sum;
        return sum + Read64(ref p, 24);
    }

    // The first block reads only narrow values; the shared test is for the widest access of the blocks.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong NarrowFirst(ref byte p, int exit)
    {
        ulong value = Read16(ref p, 2);
        if (exit == 0)
            return value;
        value += Read32(ref p, 4);
        if (exit == 1)
            return value;
        return value + Read64(ref p, 8);
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong Diamond(ref byte p, bool left)
    {
        ulong value = Read64(ref p, 0);
        if (left)
            value += Read64(ref p, 8);
        else
            value -= Read32(ref p, 12);
        return value ^ Read64(ref p, 16);
    }

    // The last block of the body jumps back to the first one. The store keeps the loads in the loop.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong LoopBack(ref byte p, int count)
    {
        ulong sum = 0;
        for (int i = 0; i < count; i++)
        {
            sum += Read64(ref p, 0);
            if ((sum & 1) != 0)
                sum ^= Read64(ref p, 8);
            sum += Read32(ref p, 16);
            _sink = sum;
        }
        return sum;
    }

    // q is reassigned between its blocks, so the accesses after that keep their own test.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong ReassignedBetweenBlocks(ref byte p, int step, int exit)
    {
        ref byte q = ref p;
        ulong sum = Read64(ref q, 0);
        if (exit == 0)
            return sum;
        q = ref Unsafe.Add(ref q, step);
        sum += Read64(ref q, 8);
        if (exit == 1)
            return sum;
        return sum + Read64(ref q, 16);
    }

    // p and q are read in every block; q moves after the first, so only p's test can be shared.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong OtherBaseMoved(ref byte p, ref byte q, int step, int exit)
    {
        ulong sum = Read64(ref p, 0) + Read64(ref q, 0);
        if (exit == 0)
            return sum;
        q = ref Unsafe.Add(ref q, step);
        sum += Read64(ref p, 8) ^ Read64(ref q, 8);
        if (exit == 1)
            return sum;
        sum += Read64(ref p, 16) - Read64(ref q, 16);
        if (exit == 2)
            return sum;
        return sum * 3;
    }

    // The limbs of in parameters from the top down, as a 256-bit compare reads them.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static ulong LessThan(in Limbs a, in Limbs b)
    {
        if (a.U3 != b.U3)
            return a.U3 < b.U3 ? 1UL : 0UL;
        if (a.U2 != b.U2)
            return a.U2 < b.U2 ? 1UL : 0UL;
        if (a.U1 != b.U1)
            return a.U1 < b.U1 ? 1UL : 0UL;
        return a.U0 < b.U0 ? 1UL : 0UL;
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void StoreChain(ref byte p, ulong value, int exit)
    {
        Unsafe.WriteUnaligned(ref p, value);
        if (exit == 0)
            return;
        Unsafe.WriteUnaligned(ref Unsafe.Add(ref p, 8), value + 1);
        if (exit == 1)
            return;
        Unsafe.WriteUnaligned(ref Unsafe.Add(ref p, 16), (uint)value + 2);
    }
}
