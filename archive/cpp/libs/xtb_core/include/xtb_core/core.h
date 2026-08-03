#ifndef _XTB_CORE_H_
#define _XTB_CORE_H_

#include <xtb_core/context_cracking.h>
#include <xtb_core/macro_helpers.h>

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

namespace xtb
{

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

#define MemoryCopy(d, s, c) memcpy((d), (s), (c));
#define MemoryMove(d, s, c) memmove((d), (s), (c));

#define GrowGeometric(old, need) ((old) ? ((old) * 2 >= (need) ? (old) * 2 : (need)) : (need))

/****************************************************************
 * Miscellaneous Macros
****************************************************************/
#define ArrLen(ARRAY) ((isize)sizeof(ARRAY) / (isize)sizeof((ARRAY)[0]))
#define Unused(X) (void)(X)

/****************************************************************
 * Control-Flow Macros
****************************************************************/
#define GenSwitchMacroIterator(VALUE, ITERATOR, MACRO) \
    Statement(switch (VALUE) { ITERATOR(MACRO) })

// Taken from https://www.gingerbill.org/article/2015/08/19/defer-in-cpp/
template <typename F>
struct privDefer {
	F f;
	privDefer(F f) : f(f) {}
	~privDefer() { f(); }
};

template <typename F>
privDefer<F> defer_func(F f) {
	return privDefer<F>(f);
}

#define DEFER_1(x, y) x##y
#define DEFER_2(x, y) DEFER_1(x, y)
#define DEFER_3(x)    DEFER_2(x, __COUNTER__)
#define defer(code)   auto DEFER_3(_defer_) = defer_func([&](){code;})

/****************************************************************
 * Type Aliases
****************************************************************/
using u8    = uint8_t;
using u16   = uint16_t;
using u32   = uint32_t;
using u64   = uint64_t;
using usize = uintptr_t;

using i8    = int8_t;
using i16   = int16_t;
using i32   = int32_t;
using i64   = int64_t;
using isize = ptrdiff_t;

using b8  = uint8_t;
using b16 = uint16_t;
using b32 = uint32_t;
using b64 = uint64_t;

using f32 = float;
using f64 = double;

using lli = long long int;
using llu = unsigned long long int;

using Flags8  = uint8_t;
using Flags16 = uint16_t;
using Flags32 = uint32_t;
using Flags64 = uint64_t;

using Mask8  = uint8_t;
using Mask16 = uint16_t;
using Mask32 = uint32_t;
using Mask64 = uint64_t;

/****************************************************************
 * Basic Math Macros
****************************************************************/
#define Min(A, B) ((A) < (B) ? (A) : (B))
#define Max(A, B) ((A) > (B) ? (A) : (B))
#define ClampTop(VALUE, MAX_VALUE) Min(VALUE, MAX_VALUE)
#define ClampBot(VALUE, MIN_VALUE) Max(VALUE, MIN_VALUE)
#define Clamp(VALUE, MIN_VALUE, MAX_VALUE) ClampBot(ClampTop(VALUE, MAX_VALUE), MIN_VALUE)

void init(int argc, char **argv);

}

#endif // _XTB_CORE_H_
