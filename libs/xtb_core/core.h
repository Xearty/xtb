#ifndef _XTB_CORE_H_
#define _XTB_CORE_H_

#include "shorthands.h"

#include <stddef.h>
#include "context_cracking.h"

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
 * Compiler Specific Attributes
****************************************************************/
#define XTB_NOINLINE __attribute__((noinline))
#define XTB_NORETURN __attribute__((noreturn))

#if XTB_COMPILER_MSVC
#define XTB_THREAD_STATIC __declspec(thread)
#elif XTB_COMPILER_CLANG || XTB_COMPILER_GCC
#define XTB_THREAD_STATIC __thread
#else
#error XTB_THREAD_STATIC not defined for this compiler.
#endif

#if XTB_LANG_CPP
#define XTB_C_LINKAGE_BEGIN \
    extern "C"              \
    {
#define XTB_C_LINKAGE_END }
#define XTB_C_LINKAGE extern "C"
#else
#define XTB_C_LINKAGE_BEGIN
#define XTB_C_LINKAGE_END
#define XTB_C_LINKAGE
#endif

/****************************************************************
 * Miscellaneous Macros
****************************************************************/
#define XTB_ArrLen(ARRAY) (sizeof(ARRAY) / sizeof((ARRAY)[0]))
#define XTB_Unused(X) (void)(X)

/****************************************************************
 * Control-Flow Macros
****************************************************************/
#define XTB_SWITCH_MACRO_ITERATOR(VALUE, ITERATOR, MACRO) \
    do { switch (VALUE) { ITERATOR(MACRO) } } while (0)

/****************************************************************
 * Type Aliases
****************************************************************/
typedef unsigned char XTB_Byte;

/****************************************************************
 * Basic Math Macros
****************************************************************/
#define XTB_Min(A, B) ((A) < (B) ? (A) : (B))
#define XTB_Max(A, B) ((A) > (B) ? (A) : (B))
#define XTB_ClampTop(VALUE, MAX_VALUE) XTB_Min(VALUE, MAX_VALUE)
#define XTB_ClampBot(VALUE, MIN_VALUE) XTB_Max(VALUE, MIN_VALUE)
#define XTB_Clamp(VALUE, MIN_VALUE, MAX_VALUE) XTB_ClampBot(XTB_ClampTop(VALUE, MAX_VALUE), MIN_VALUE)

XTB_C_LINKAGE_BEGIN

/****************************************************************
 * Initialization
****************************************************************/
void xtb_init(int argc, char **argv);

/****************************************************************
 * Logging
****************************************************************/
typedef enum XTB_Log_Level
{
    XTB_LOG_TRACE = 0,
    XTB_LOG_DEBUG,
    XTB_LOG_INFO,
    XTB_LOG_WARN,
    XTB_LOG_ERROR,
    XTB_LOG_FATAL,
} XTB_Log_Level;

typedef void (*XTB_Log_Callback)(XTB_Log_Level level, const char *message, void *user_data);

void xtb_set_log_callback(XTB_Log_Callback cb, void *user_data);
void xtb_set_trace_log_level(int log_level);
void xtb_log(XTB_Log_Level level, const char *fmt, ...);

#define XTB_LOG_TRACE(fmt, ...) xtb_log(XTB_LOG_TRACE, fmt, ##__VA_ARGS__)
#define XTB_LOG_DEBUG(fmt, ...) xtb_log(XTB_LOG_DEBUG, fmt, ##__VA_ARGS__)
#define XTB_LOG_INFO(fmt, ...)  xtb_log(XTB_LOG_INFO,  fmt, ##__VA_ARGS__)
#define XTB_LOG_WARN(fmt, ...)  xtb_log(XTB_LOG_WARN,  fmt, ##__VA_ARGS__)
#define XTB_LOG_ERROR(fmt, ...) xtb_log(XTB_LOG_ERROR, fmt, ##__VA_ARGS__)
#define XTB_LOG_FATAL(fmt, ...) xtb_log(XTB_LOG_FATAL, fmt, ##__VA_ARGS__)

/****************************************************************
 * Assertions and Panic System
****************************************************************/
typedef void (*XTB_Panic_Handler)(const char *message, void *user_data);

void xtb_set_panic_handler(XTB_Panic_Handler handler, void *user_data);
void xtb_panic(const char *fmt, ...);

#ifndef NDEBUG
#   define XTB_ASSERT(cond)                                                           \
        do                                                                            \
        {                                                                             \
            if (!(cond))                                                              \
            {                                                                         \
                xtb_panic("Assertion failed: %s (%s:%d)", #cond, __FILE__, __LINE__); \
            }                                                                         \
        } while (0)

#   define XTB_UNREACHABLE                                                      \
        do                                                                      \
        {                                                                       \
            xtb_panic("Unreachable line reached (%s:%d)",  __FILE__, __LINE__); \
        } while (0)
#else
#   define XTB_ASSERT(cond) (void)(cond)
#   define XTB_UNREACHABLE
#endif

#define XTB_STATIC_ASSERT(cond, msg) \
    typedef char static_assertion_##msg[(cond) ? 1 : -1]

/****************************************************************
 * Stack Trace
****************************************************************/
void xtb_print_stack_trace(int skip_frames_count);
void xtb_print_full_stack_trace(void);

XTB_C_LINKAGE_END

#endif // _XTB_CORE_H_
