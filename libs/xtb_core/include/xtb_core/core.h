#ifndef _XTB_CORE_H_
#define _XTB_CORE_H_

#include <xtb_core/shorthands.h>
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
#define XTB_Bytes(N) (N)
#define XTB_Kilobytes(N) (1024 * XTB_Bytes(N))
#define XTB_Megabytes(N) (1024 * XTB_Kilobytes(N))
#define XTB_Gigabytes(N) (1024 * XTB_Megabytes(N))
#define XTB_Terabytes(N) (1024 * XTB_Gigabytes(N))

#define XTB_MemoryZero(s, z) memset((s), 0, (z))
#define XTB_MemoryZeroStruct(s) XTB_MemoryZero((s), sizeof(*(s)))
#define XTB_MemoryZeroArray(a) XTB_MemoryZero((a), sizeof(a))
#define XTB_MemoryZeroTyped(m, c) XTB_MemoryZero((m), sizeof(*(m)) * (c))

#define XTB_MemoryCopy(s, d, c) memcpy((s), (d), (c));
#define XTB_MemoryMove(s, d, c) memmove((s), (d), (c));

#define XTB_GrowGeometric(old, need) ((old) ? ((old) * 2 >= (need) ? (old) * 2 : (need)) : (need))

/****************************************************************
 * Miscellaneous Macros
****************************************************************/
#define XTB_ArrLen(ARRAY) (sizeof(ARRAY) / sizeof((ARRAY)[0]))
#define XTB_Unused(X) (void)(X)

/****************************************************************
 * Control-Flow Macros
****************************************************************/
#define XTB_SWITCH_MACRO_ITERATOR(VALUE, ITERATOR, MACRO) \
    XTB_Statement(switch (VALUE) { ITERATOR(MACRO) })

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

typedef u8 XTB_Byte;

/****************************************************************
 * Basic Math Macros
****************************************************************/
#define XTB_Min(A, B) ((A) < (B) ? (A) : (B))
#define XTB_Max(A, B) ((A) > (B) ? (A) : (B))
#define XTB_ClampTop(VALUE, MAX_VALUE) XTB_Min(VALUE, MAX_VALUE)
#define XTB_ClampBot(VALUE, MIN_VALUE) XTB_Max(VALUE, MIN_VALUE)
#define XTB_Clamp(VALUE, MIN_VALUE, MAX_VALUE) XTB_ClampBot(XTB_ClampTop(VALUE, MAX_VALUE), MIN_VALUE)

XTB_C_LINKAGE_BEGIN

void xtb_init(int argc, char **argv);

XTB_C_LINKAGE_END

#endif // _XTB_CORE_H_
