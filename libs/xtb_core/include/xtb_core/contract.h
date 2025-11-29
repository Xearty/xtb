#ifndef _XTB_CONTRACT_H_
#define _XTB_CONTRACT_H_

#include <xtb_core/panic.h>
#include <xtb_core/intrinsics.h>
#include <xtb_core/macro_helpers.h>

#ifndef NDEBUG
#   define Assert(cond)                                                           \
        Statement({                                                               \
            if (Unlikely(!(cond)))                                                \
            {                                                                         \
                panic("Assertion failed: %s (%s:%d)", #cond, __FILE__, __LINE__); \
            }                                                                         \
        })
#else
#   define Assert(cond) (void)(cond)
#endif

#define Unreachable                                                      \
    Statement({                                                         \
        panic("Unreachable line reached (%s:%d)",  __FILE__, __LINE__); \
    })

#define CheckBounds(i, count, ...) Assert(0 <= (i) && (i) <= count)

#if LANG_C
#if COMPILER_GCC || COMPILER_CLANG
#define StaticAssert(cond, msg) _Static_assert((cond), msg)
#else
#error StaticAssert not defined for compiler
#endif
#else
#define StaticAssert(cond, msg) static_assert((cond), msg)
#endif


#endif // _XTB_CONTRACT_H_
