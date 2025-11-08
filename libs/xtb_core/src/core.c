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
#include "logger.c"
#include "panic.c"

void xtb_init(int argc, char **argv)
{
    const char *exe_path = argv[0];
    g_backtrace.state = backtrace_create_state(exe_path, 0, xtb_backtrace_error_callback, NULL);

    allocators_init();

    register_signal_handlers();
}

