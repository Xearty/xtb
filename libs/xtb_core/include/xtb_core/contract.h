#ifndef _XTB_CONTRACT_H_
#define _XTB_CONTRACT_H_

#include <xtb_core/panic.h>
#include <xtb_core/intrinsics.h>
#include <xtb_core/macro_helpers.h>

#ifndef NDEBUG
#   define XTB_ASSERT(cond)                                                           \
        XTB_Statement({                                                               \
            if (XTB_Unlikely(!(cond)))                                                \
            {                                                                         \
                xtb_panic("Assertion failed: %s (%s:%d)", #cond, __FILE__, __LINE__); \
            }                                                                         \
        })

#   define XTB_UNREACHABLE                                                      \
        XTB_Statement({                                                         \
            xtb_panic("Unreachable line reached (%s:%d)",  __FILE__, __LINE__); \
        })

#define XTB_CheckBounds(i, count, ...) XTB_ASSERT(0 <= (i) && (i) <= count)

#else
#   define XTB_ASSERT(cond) (void)(cond)
#   define XTB_UNREACHABLE
#endif

#define XTB_STATIC_ASSERT(cond, msg) \
    typedef char static_assertion_##msg[(cond) ? 1 : -1]

#endif // _XTB_CONTRACT_H_
