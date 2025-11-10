#ifndef _XTB_CORE_H_
#define _XTB_CORE_H_

#include <xtb_core/context_cracking.h>
#include <xtb_core/macro_helpers.h>

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/****************************************************************
 * Versioning
****************************************************************/
#define XTB_CORE_VERSION_MAJOR 0
#define XTB_CORE_VERSION_MINOR 0
#define XTB_CORE_VERSION_PATCH 1
#define XTB_CORE_VERSION_STRING "0.0.1"

/****************************************************************
 * Memory Utilities
****************************************************************/
#define Bytes(N) (N)
#define Kilobytes(N) (1024 * Bytes(N))
#define Megabytes(N) (1024 * Kilobytes(N))
#define Gigabytes(N) (1024 * Megabytes(N))
#define Terabytes(N) (1024 * Gigabytes(N))

#define MemoryZero(s, z) memset((s), 0, (z))
#define MemoryZeroStruct(s) MemoryZero((s), sizeof(*(s)))
#define MemoryZeroArray(a) MemoryZero((a), sizeof(a))
#define MemoryZeroTyped(m, c) MemoryZero((m), sizeof(*(m)) * (c))

#define MemoryCopy(s, d, c) memcpy((s), (d), (c));
#define MemoryMove(s, d, c) memmove((s), (d), (c));

#define GrowGeometric(old, need) ((old) ? ((old) * 2 >= (need) ? (old) * 2 : (need)) : (need))

/****************************************************************
 * Miscellaneous Macros
****************************************************************/
#define ArrLen(ARRAY) (sizeof(ARRAY) / sizeof((ARRAY)[0]))
#define Unused(X) (void)(X)

/****************************************************************
 * Control-Flow Macros
****************************************************************/
#define SWITCH_MACRO_ITERATOR(VALUE, ITERATOR, MACRO) \
    Statement(switch (VALUE) { ITERATOR(MACRO) })

/****************************************************************
 * Type Aliases
****************************************************************/
typedef uint8_t     u8;
typedef uint16_t    u16;
typedef uint32_t    u32;
typedef uint64_t    u64;
typedef uint64_t    usize;

typedef int8_t      i8;
typedef int16_t     i16;
typedef int32_t     i32;
typedef int64_t     i64;
typedef int64_t     isize;

typedef bool        b8;
typedef uint16_t    b16;
typedef uint32_t    b32;
typedef uint64_t    b64;

typedef float       f32;
typedef double      f64;

typedef long long int      lli;
typedef unsigned long long llu;

typedef u8  Flags8;
typedef u16 Flags16;
typedef u32 Flags32;
typedef u64 Flags64;

typedef u8  Mask8;
typedef u16 Mask16;
typedef u32 Mask32;
typedef u64 Mask64;

/****************************************************************
 * Basic Math Macros
****************************************************************/
#define Min(A, B) ((A) < (B) ? (A) : (B))
#define Max(A, B) ((A) > (B) ? (A) : (B))
#define ClampTop(VALUE, MAX_VALUE) Min(VALUE, MAX_VALUE)
#define ClampBot(VALUE, MIN_VALUE) Max(VALUE, MIN_VALUE)
#define Clamp(VALUE, MIN_VALUE, MAX_VALUE) ClampBot(ClampTop(VALUE, MAX_VALUE), MIN_VALUE)

C_LINKAGE_BEGIN

void xtb_init(int argc, char **argv);

C_LINKAGE_END

#endif // _XTB_CORE_H_
