// SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
// SPDX-License-Identifier: MIT

using System;
using System.Runtime.CompilerServices;

internal static class Program
{
    private struct Payload
    {
        public long A, B, C;
    }

    private sealed class Holder;

    private static Holder s_holder = null!;
    private static object s_box = null!;

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void AllocateHolder() => s_holder = new Holder();

    // Escaping through a static prevents the box from being removed or stack allocated.
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void AllocateBox(long last) => s_box = new Payload { A = 1, B = 2, C = last };

    private static int Main()
    {
        AllocateHolder();
        _ = RuntimeHelpers.GetHashCode(s_holder);
        AllocateBox(0);
        _ = RuntimeHelpers.GetHashCode(s_box);

        // Warm up hashing and boxing before placing the two allocations next to each other.
        AllocateHolder();
        int before = RuntimeHelpers.GetHashCode(s_holder);
        AllocateBox(0);
        int after = RuntimeHelpers.GetHashCode(s_holder);
        bool hashPreserved = before == after;
        bool fieldsPreserved = ((Payload)s_box).A == 1 && ((Payload)s_box).B == 2 && ((Payload)s_box).C == 0;

        AllocateHolder();
        AllocateBox(0);
        long lastBeforeHash = ((Payload)s_box).C;
        _ = RuntimeHelpers.GetHashCode(s_holder);
        long lastAfterHash = ((Payload)s_box).C;

        if (!hashPreserved || !fieldsPreserved || lastBeforeHash != lastAfterHash)
        {
            Console.WriteLine("Inline boxing corrupted the adjacent object's header or the boxed payload.");
            return 1;
        }

        Console.WriteLine("Inline boxing regression passed.");
        return 0;
    }
}
