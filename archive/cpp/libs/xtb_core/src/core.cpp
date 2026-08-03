#include <xtb_core/core.h>
#include <xtb_core/allocator.h>
#include <xtb_core/stacktrace.h>

#if OS_LINUX
#include "linux_signal_handlers.cpp"
#else
#define register_signal_handlers(...)
#endif

#include "string.cpp"
#include "arena.cpp"
#include "thread_context.cpp"
#include "allocator.cpp"
#include "array.cpp"
#include "stacktrace/stacktrace.cpp"
#include "logger.cpp"
#include "panic.cpp"

namespace xtb
{
void init(int argc, char **argv)
{
    Unused(argc);
    const char *exe_path = argv[0];

    allocators_init();
    stacktrace::init(exe_path);
    register_signal_handlers();
}
}

