// SPDX-FileCopyrightText: 2026 Demerzel Solutions Limited
// SPDX-License-Identifier: MIT

#define C_FUNC(name) name
#define LOCAL_LABEL(name) .L##name
#define OFFSETOF__ee_alloc_context 0
#define OFFSETOF__ee_alloc_context__alloc_ptr 0
#define OFFSETOF__ee_alloc_context__combined_limit 8
#define OFFSETOF__MethodTable__m_usComponentSize 0
#define OFFSETOF__Object__m_pEEType 0
#define OFFSETOF__Array__m_Length 8
#define STRING_BASE_SIZE 22
#define SZARRAY_BASE_SIZE 24
#define MAX_STRING_LENGTH 0x3fffffdf

.text
.macro INLINE_GET_ALLOC_CONTEXT_BASE
    call test_tls_get_addr
.endm

#include "allocfast.inc"

// Model a legal TLS resolver that clobbers the incoming allocation size.
.global test_tls_get_addr
test_tls_get_addr:
    la a0, allocation_context
    li a1, -1
    li t0, 8
    li t1, -1
    li t2, -1
    li t3, -1
    li t4, -1
    li t5, -1
    li t6, -1
    ret

.section .note.GNU-stack,"",@progbits
