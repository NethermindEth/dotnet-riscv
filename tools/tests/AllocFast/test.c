// SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct {
    uint8_t *ptr;
    uint8_t *limit;
} allocation_context;

extern void *RhNewString(void *method_table, uintptr_t count);
extern void *RhpNewArrayFast(void *method_table, uintptr_t count);
extern void *RhpNewPtrArrayFast(void *method_table, uintptr_t count);

static void *slow_method_table;
static uintptr_t slow_count;
static unsigned slow_calls;

void *RhpNewVariableSizeObject(void *method_table, uintptr_t count)
{
    slow_method_table = method_table;
    slow_count = count;
    slow_calls++;
    return NULL;
}

void RhExceptionHandling_FailedAllocation(void *method_table, uintptr_t overflow)
{
    (void)method_table;
    (void)overflow;
    abort();
}

int main(void)
{
    const struct {
        const char *name;
        void *(*allocate)(void *, uintptr_t);
        uint16_t component_size;
        unsigned base_size;
    } helpers[] = {
        {"string", RhNewString, 2, 22},
        {"array", RhpNewArrayFast, 3, 24},
        {"pointer array", RhpNewPtrArrayFast, 8, 24},
    };
    const uintptr_t counts[] = {0, 1, 5, 17};
    _Alignas(16) uint8_t heap[1024];
    unsigned failures = 0;
    unsigned cases = 0;
    for (unsigned h = 0; h < sizeof(helpers) / sizeof(helpers[0]); h++) {
        for (unsigned n = 0; n < sizeof(counts) / sizeof(counts[0]); n++) {
            uintptr_t count = counts[n];
            size_t size = (helpers[h].base_size + count * helpers[h].component_size + 7) & ~(size_t)7;
            for (unsigned fits = 0; fits <= 1; fits++) {
                memset(heap, 0, sizeof(heap));
                allocation_context.ptr = heap;
                allocation_context.limit = heap + size - (fits ? 0 : 8);
                slow_calls = 0;
                uint16_t method_table = helpers[h].component_size;
                void *result = helpers[h].allocate(&method_table, count);
                int ok;
                if (fits) {
                    uintptr_t stored_method_table, stored_count;
                    memcpy(&stored_method_table, heap, sizeof(stored_method_table));
                    memcpy(&stored_count, heap + 8, sizeof(stored_count));
                    ok = result == heap && allocation_context.ptr == heap + size && slow_calls == 0
                        && stored_method_table == (uintptr_t)&method_table && stored_count == count;
                    // An exact fit must leave the next allocation on the slow path.
                    ok &= helpers[h].allocate(&method_table, count) == NULL && slow_calls == 1;
                    ok &= allocation_context.ptr == heap + size;
                } else {
                    ok = result == NULL && allocation_context.ptr == heap && slow_calls == 1;
                    for (unsigned i = 0; i < sizeof(heap); i++)
                        ok &= heap[i] == 0;
                }
                ok &= slow_method_table == &method_table && slow_count == count;
                cases++;
                if (!ok) {
                    fprintf(stderr, "%s count=%lu fits=%u failed\n", helpers[h].name, (unsigned long)count, fits);
                    failures++;
                }
            }
        }
    }
    printf("AllocFast: %u cases, %u failures\n", cases, failures);
    return failures != 0;
}
