#include <xtb_core/core.h>
#include <xtb_core/allocator.h>
#include <xtb_core/stacktrace.h>

#if OS_LINUX
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

    allocators_init();
    stacktrace_init(exe_path);
    register_signal_handlers();
}

