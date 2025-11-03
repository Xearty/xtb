#ifndef _XTB_CORE_H_
#define _XTB_CORE_H_

#include <stddef.h>

/****************************************************************
 * Versioning
****************************************************************/
#define XTB_CORE_VERSION_MAJOR 0
#define XTB_CORE_VERSION_MINOR 0
#define XTB_CORE_VERSION_PATCH 1
#define XTB_CORE_VERSION_STRING "0.0.1"

/****************************************************************
  Allocator Interface
****************************************************************/
typedef void*(*XTB_Allocate_Fn)(void*, size_t);
typedef void(*XTB_Deallocate_Fn)(void*, void*);

typedef struct XTB_Allocator
{
    void *context;
    XTB_Allocate_Fn allocate;
    XTB_Deallocate_Fn deallocate;
} XTB_Allocator;

#define XTB_AllocateArray(allocator, type, count) (type*)(allocator.allocate(allocator.context, sizeof(type) * (count)))
#define XTB_Allocate(allocator, type) XTB_AllocateArray(allocator, type, 1)
#define XTB_Deallocate(allocator, ptr) allocator.deallocate(allocator.context, ptr)

/****************************************************************
 * Initialization
****************************************************************/
void xtb_init(int argc, char **argv);

/****************************************************************
 * Memory Utilities
****************************************************************/
#define XTB_BYTES(N) (N)
#define XTB_KILOBYTES(N) (1024 * XTB_BYTES(N))
#define XTB_MEGABYTES(N) (1024 * XTB_KILOBYTES(N))
#define XTB_GIGABYTES(N) (1024 * XTB_MEGABYTES(N))
#define XTB_TERABYTES(N) (1024 * XTB_GIGABYTES(N))

/****************************************************************
 * Function Attributes
****************************************************************/
#define XTB_NOINLINE __attribute__((noinline))
#define XTB_NORETURN __attribute__((noreturn))

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

/****************************************************************
 * Miscellaneous Macros
****************************************************************/
#define XTB_ARRLEN(ARRAY) (sizeof(ARRAY) / sizeof((ARRAY)[0]))

/****************************************************************
 * Control-Flow Macros
****************************************************************/
#define XTB_SWITCH_MACRO_ITERATOR(VALUE, ITERATOR, MACRO) \
    do { switch (VALUE) { ITERATOR(MACRO) } } while (0)

/****************************************************************
 * Type Aliases
****************************************************************/
typedef unsigned char XTB_Byte;

#endif // _XTB_CORE_H_
