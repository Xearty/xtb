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

#   define Unreachable                                                      \
        Statement({                                                         \
            panic("Unreachable line reached (%s:%d)",  __FILE__, __LINE__); \
        })

#define CheckBounds(i, count, ...) Assert(0 <= (i) && (i) <= count)

#else
#   define Assert(cond) (void)(cond)
#   define Unreachable
#endif

#define StaticAssert(cond, msg) \
    typedef char static_assertion_##msg[(cond) ? 1 : -1]

#endif // _XTB_CONTRACT_H_
