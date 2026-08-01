/*
 * Soft libatomic for the single-hart zkVM guest (rv64im, no A extension).
 *
 * The GCC libatomic that Alpine ships is built for rv64gc: its atomics use
 * lr/sc and, for sizes the hardware cannot do lock-free, a pthread lock table.
 * The zkVM guest decodes only base rv64im and runs on a single hart, so every
 * atomic operation is trivially race-free — a plain load/modify/store. This
 * drop-in libatomic provides the full __atomic_* ABI with exactly that: no
 * lr/sc, no locks, no pthread. memory_order arguments are ignored; a compiler
 * barrier preserves intra-thread ordering, which is all a single hart needs.
 */
/* Freestanding: avoid libc headers (the lp64 soft-float cross toolchain has no
   gnu/stubs-lp64.h). Declare the few things we need ourselves; memcpy/memcmp
   resolve from the guest libc at link time. */
typedef __SIZE_TYPE__ size_t;
extern void *memcpy(void *, const void *, size_t);
extern int   memcmp(const void *, const void *, size_t);

typedef unsigned char       u8;
typedef unsigned short      u16;
typedef unsigned int        u32;
typedef unsigned long long  u64;
typedef unsigned __int128   u128;

#define BARRIER() __asm__ __volatile__("" ::: "memory")

#define SIZED(N, T)                                                            \
T __atomic_load_##N(const volatile void *p, int mo) {                          \
    (void)mo; BARRIER(); T v = *(const volatile T *)p; BARRIER(); return v;    \
}                                                                             \
void __atomic_store_##N(volatile void *p, T v, int mo) {                       \
    (void)mo; BARRIER(); *(volatile T *)p = v; BARRIER();                      \
}                                                                             \
T __atomic_exchange_##N(volatile void *p, T v, int mo) {                       \
    (void)mo; BARRIER(); T o = *(volatile T *)p; *(volatile T *)p = v;         \
    BARRIER(); return o;                                                       \
}                                                                             \
_Bool __atomic_compare_exchange_##N(volatile void *p, void *exp, T des,        \
                                    int weak, int su, int fa) {                \
    (void)weak; (void)su; (void)fa; BARRIER();                                 \
    T cur = *(volatile T *)p;                                                  \
    if (cur == *(T *)exp) { *(volatile T *)p = des; BARRIER(); return 1; }     \
    *(T *)exp = cur; BARRIER(); return 0;                                      \
}                                                                             \
T __atomic_fetch_add_##N(volatile void *p, T v, int mo) {                      \
    (void)mo; BARRIER(); T o = *(volatile T *)p; *(volatile T *)p = o + v;     \
    BARRIER(); return o;                                                       \
}                                                                             \
T __atomic_fetch_sub_##N(volatile void *p, T v, int mo) {                      \
    (void)mo; BARRIER(); T o = *(volatile T *)p; *(volatile T *)p = o - v;     \
    BARRIER(); return o;                                                       \
}                                                                             \
T __atomic_fetch_and_##N(volatile void *p, T v, int mo) {                      \
    (void)mo; BARRIER(); T o = *(volatile T *)p; *(volatile T *)p = o & v;     \
    BARRIER(); return o;                                                       \
}                                                                             \
T __atomic_fetch_or_##N(volatile void *p, T v, int mo) {                       \
    (void)mo; BARRIER(); T o = *(volatile T *)p; *(volatile T *)p = o | v;     \
    BARRIER(); return o;                                                       \
}                                                                             \
T __atomic_fetch_xor_##N(volatile void *p, T v, int mo) {                      \
    (void)mo; BARRIER(); T o = *(volatile T *)p; *(volatile T *)p = o ^ v;     \
    BARRIER(); return o;                                                       \
}                                                                             \
T __atomic_fetch_nand_##N(volatile void *p, T v, int mo) {                     \
    (void)mo; BARRIER(); T o = *(volatile T *)p; *(volatile T *)p = ~(o & v);  \
    BARRIER(); return o;                                                       \
}                                                                             \
T __atomic_add_fetch_##N(volatile void *p, T v, int mo) {                      \
    return __atomic_fetch_add_##N(p, v, mo) + v;                               \
}                                                                             \
T __atomic_sub_fetch_##N(volatile void *p, T v, int mo) {                      \
    return __atomic_fetch_sub_##N(p, v, mo) - v;                               \
}                                                                             \
T __atomic_and_fetch_##N(volatile void *p, T v, int mo) {                      \
    return __atomic_fetch_and_##N(p, v, mo) & v;                               \
}                                                                             \
T __atomic_or_fetch_##N(volatile void *p, T v, int mo) {                       \
    return __atomic_fetch_or_##N(p, v, mo) | v;                                \
}                                                                             \
T __atomic_xor_fetch_##N(volatile void *p, T v, int mo) {                      \
    return __atomic_fetch_xor_##N(p, v, mo) ^ v;                               \
}                                                                             \
T __atomic_nand_fetch_##N(volatile void *p, T v, int mo) {                     \
    T o = __atomic_fetch_nand_##N(p, v, mo); return ~(o & v);                  \
}

SIZED(1, u8)
SIZED(2, u16)
SIZED(4, u32)
SIZED(8, u64)
SIZED(16, u128)

/* Generic, variable-size forms (used for over-large or unknown-size atomics). */
void __atomic_load(size_t n, const volatile void *p, void *ret, int mo) {
    (void)mo; BARRIER(); memcpy(ret, (const void *)p, n); BARRIER();
}
void __atomic_store(size_t n, volatile void *p, void *val, int mo) {
    (void)mo; BARRIER(); memcpy((void *)p, val, n); BARRIER();
}
void __atomic_exchange(size_t n, volatile void *p, void *val, void *ret, int mo) {
    (void)mo; BARRIER(); memcpy(ret, (void *)p, n); memcpy((void *)p, val, n);
    BARRIER();
}
_Bool __atomic_compare_exchange(size_t n, volatile void *p, void *exp,
                                void *des, int su, int fa) {
    (void)su; (void)fa; BARRIER();
    if (memcmp((void *)p, exp, n) == 0) {
        memcpy((void *)p, des, n); BARRIER(); return 1;
    }
    memcpy(exp, (void *)p, n); BARRIER(); return 0;
}

_Bool __atomic_is_lock_free(size_t n, const volatile void *p) {
    (void)p; return n <= 16; /* single hart: everything is effectively lock-free */
}

_Bool __atomic_test_and_set(volatile void *p, int mo) {
    (void)mo; BARRIER(); u8 o = *(volatile u8 *)p; *(volatile u8 *)p = 1;
    BARRIER(); return o != 0;
}
void __atomic_clear(volatile void *p, int mo) {
    (void)mo; BARRIER(); *(volatile u8 *)p = 0; BARRIER();
}

/* No FP environment on the guest; nothing to raise. */
void __atomic_feraiseexcept(int e) { (void)e; }
