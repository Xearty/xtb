#include <stdarg.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <backtrace.h>

#include <xtb_core/core.h>
#include <xtb_core/context_cracking.h>
#include <xtb_core/logger.h>
#include <xtb_ansi/ansi.h>

#if XTB_OS_LINUX
#include "linux_signal_handlers.c"
#else
#define register_signal_handlers(...)
#endif

#include "str.c"
#include "str_buffer.c"
#include "arena.c"
#include "thread_context.c"
#include "allocator.c"
#include "array.c"
#include "stacktrace.c"

/****************************************************************
 * Logging
****************************************************************/
typedef struct XTB_Logger
{
    XTB_Log_Callback cb;
    void *user_data;
    XTB_Log_Level level_filter_threshold;
} XTB_Logger;

XTB_Logger g_logger;

void xtb_set_log_callback(XTB_Log_Callback cb, void *user_data)
{
    g_logger.cb = cb;
    g_logger.user_data = user_data;
}

void xtb_set_trace_log_level(int log_level)
{
    g_logger.level_filter_threshold = log_level;
}

void xtb_log(XTB_Log_Level level, const char *fmt, ...)
{
    if (level < g_logger.level_filter_threshold) return;

    const char *level_str[] = { "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL" };
    const char *level_style[] = { HBLK, HBLU, GRN, YEL, HRED, BHRED };

    char buffer[1024];

    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);

    if (g_logger.cb)
    {
        g_logger.cb(level, buffer, g_logger.user_data);
    }
    else
    {
        xtb_ansi_print_style(stderr, level_style[level], "[%s] %s", level_str[level], buffer);
        fputs("\n", stderr);
    }
}

/****************************************************************
 * Assertions and Panic System
****************************************************************/
typedef struct XTB_Panic
{
    XTB_Panic_Handler handler;
    void *user_data;
} XTB_Panic;

XTB_Panic g_panic;

void xtb_set_panic_handler(XTB_Panic_Handler handler, void *user_data)
{
    g_panic.handler = handler;
    g_panic.user_data = user_data;
}

void xtb_panic(const char *fmt, ...)
{
    char buffer[1024];

    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);

    xtb_log(XTB_LOG_FATAL, "%s", buffer);

    if (g_panic.handler)
    {
        g_panic.handler(buffer, g_panic.user_data);
    }

    fflush(stdout);
    fflush(stderr);
    abort();
}

/****************************************************************
 * Initialization
****************************************************************/
void xtb_init(int argc, char **argv)
{
    const char *exe_path = argv[0];
    g_backtrace.state = backtrace_create_state(exe_path, 0, xtb_backtrace_error_callback, NULL);

    allocators_init();

    register_signal_handlers();
}

