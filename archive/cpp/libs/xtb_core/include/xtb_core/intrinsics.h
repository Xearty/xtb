#ifndef _XTB_INTRINSICS_H_
#define _XTB_INTRINSICS_H_

#include <xtb_core/context_cracking.h>

#define noinline __attribute__((noinline))
#define noreturn __attribute__((noreturn))

#if COMPILER_MSVC
#define thread_local __declspec(thread)
#elif COMPILER_CLANG || COMPILER_GCC
#define thread_local __thread
#else
#error thread_local not defined for this compiler.
#endif

#ifdef COMPILER_GCC
#define Likely(x)      __builtin_expect(!!(x), 1)
#define Unlikely(x)    __builtin_expect(!!(x), 0)
#else
#define Likely(x)      (x)
#define Unlikely(x)    (x)
#endif

#endif // _XTB_INTRINSICS_H_
