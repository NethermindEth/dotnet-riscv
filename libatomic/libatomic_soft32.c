/*
 * The __atomic_* libcall ABI for the single-hart rv32im zkVM guest, as plain
 * load/modify/store: libatomic_soft.c for a 32-bit target built with clang.
 *
 * clang rejects definitions of functions it treats as builtins even with
 * -fno-builtin, so every function is defined under a private name and given its
 * ABI name through an asm label. There is no __int128 on rv32, so sizes stop at 8.
 */
typedef __SIZE_TYPE__ size_t;
extern void *memcpy(void *, const void *, size_t);
extern int   memcmp(const void *, const void *, size_t);

typedef unsigned char      u8;
typedef unsigned short     u16;
typedef unsigned int       u32;
typedef unsigned long long u64;

#define BARRIER() __asm__ __volatile__("" ::: "memory")
#define ABI(name) __asm__(#name)

#define SIZED(N, T)                                                                      \
T load_##N(const volatile void *p, int mo) ABI(__atomic_load_##N);                       \
T load_##N(const volatile void *p, int mo) {                                             \
    (void)mo; BARRIER(); T v = *(const volatile T *)p; BARRIER(); return v;              \
}                                                                                        \
void store_##N(volatile void *p, T v, int mo) ABI(__atomic_store_##N);                   \
void store_##N(volatile void *p, T v, int mo) {                                          \
    (void)mo; BARRIER(); *(volatile T *)p = v; BARRIER();                                \
}                                                                                        \
T exchange_##N(volatile void *p, T v, int mo) ABI(__atomic_exchange_##N);                \
T exchange_##N(volatile void *p, T v, int mo) {                                          \
    (void)mo; BARRIER(); T o = *(volatile T *)p; *(volatile T *)p = v;                   \
    BARRIER(); return o;                                                                 \
}                                                                                        \
_Bool cmpxchg_##N(volatile void *p, void *exp, T des, int weak, int su, int fa)          \
    ABI(__atomic_compare_exchange_##N);                                                  \
_Bool cmpxchg_##N(volatile void *p, void *exp, T des, int weak, int su, int fa) {        \
    (void)weak; (void)su; (void)fa; BARRIER();                                           \
    T cur = *(volatile T *)p;                                                            \
    if (cur == *(T *)exp) { *(volatile T *)p = des; BARRIER(); return 1; }               \
    *(T *)exp = cur; BARRIER(); return 0;                                                \
}                                                                                        \
FETCH(N, T, add, o + v)                                                                  \
FETCH(N, T, sub, o - v)                                                                  \
FETCH(N, T, and, o & v)                                                                  \
FETCH(N, T, or, o | v)                                                                   \
FETCH(N, T, xor, o ^ v)                                                                  \
FETCH(N, T, nand, ~(o & v))

/* __atomic_fetch_OP_N returns the old value, __atomic_OP_fetch_N the new one. */
#define FETCH(N, T, OP, EXPR)                                                            \
T fetch_##OP##_##N(volatile void *p, T v, int mo) ABI(__atomic_fetch_##OP##_##N);        \
T fetch_##OP##_##N(volatile void *p, T v, int mo) {                                      \
    (void)mo; BARRIER(); T o = *(volatile T *)p; *(volatile T *)p = (EXPR);              \
    BARRIER(); return o;                                                                 \
}                                                                                        \
T OP##_fetch_##N(volatile void *p, T v, int mo) ABI(__atomic_##OP##_fetch_##N);          \
T OP##_fetch_##N(volatile void *p, T v, int mo) {                                        \
    (void)mo; BARRIER(); T o = *(volatile T *)p; T n = (EXPR); *(volatile T *)p = n;     \
    BARRIER(); return n;                                                                 \
}

SIZED(1, u8)
SIZED(2, u16)
SIZED(4, u32)
SIZED(8, u64)

void load_any(size_t n, const volatile void *p, void *ret, int mo) ABI(__atomic_load);
void load_any(size_t n, const volatile void *p, void *ret, int mo) {
    (void)mo; BARRIER(); memcpy(ret, (const void *)p, n); BARRIER();
}
void store_any(size_t n, volatile void *p, void *val, int mo) ABI(__atomic_store);
void store_any(size_t n, volatile void *p, void *val, int mo) {
    (void)mo; BARRIER(); memcpy((void *)p, val, n); BARRIER();
}
void exchange_any(size_t n, volatile void *p, void *val, void *ret, int mo) ABI(__atomic_exchange);
void exchange_any(size_t n, volatile void *p, void *val, void *ret, int mo) {
    (void)mo; BARRIER(); memcpy(ret, (const void *)p, n); memcpy((void *)p, val, n); BARRIER();
}
_Bool cmpxchg_any(size_t n, volatile void *p, void *exp, void *des, int su, int fa) ABI(__atomic_compare_exchange);
_Bool cmpxchg_any(size_t n, volatile void *p, void *exp, void *des, int su, int fa) {
    (void)su; (void)fa; BARRIER();
    if (memcmp((const void *)p, exp, n) == 0) { memcpy((void *)p, des, n); BARRIER(); return 1; }
    memcpy(exp, (const void *)p, n); BARRIER(); return 0;
}
_Bool is_lock_free(size_t n, const volatile void *p) ABI(__atomic_is_lock_free);
_Bool is_lock_free(size_t n, const volatile void *p) {
    (void)n; (void)p; return 1;
}
