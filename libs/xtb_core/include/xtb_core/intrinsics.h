#ifndef _XTB_INTRINSICS_H_
#define _XTB_INTRINSICS_H_

#include <xtb_core/context_cracking.h>

#define XTB_NOINLINE __attribute__((noinline))
#define XTB_NORETURN __attribute__((noreturn))

#if XTB_COMPILER_MSVC
#define XTB_THREAD_STATIC __declspec(thread)
#elif XTB_COMPILER_CLANG || XTB_COMPILER_GCC
#define XTB_THREAD_STATIC __thread
#else
#error XTB_THREAD_STATIC not defined for this compiler.
#endif

#ifdef XTB_COMPILER_GCC
#define XTB_Likely(x)      __builtin_expect(!!(x), 1)
#define XTB_Unlikely(x)    __builtin_expect(!!(x), 0)
#else
#define XTB_Likely(x)      (x)
#define XTB_Unlikely(x)    (x)
#endif

#endif // _XTB_INTRINSICS_H_
