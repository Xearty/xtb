#include <xtb_core/panic.h>
#include <xtb_core/logger.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

namespace xtb
{

struct Panic
{
    PanicHandler handler;
    void *user_data;

    int exit_code;
    bool panic_in_flight;
};

Panic g_panic;

void panic_set_exit_code(int code)
{
    g_panic.exit_code = code;
}

void panic_set_handler(PanicHandler handler, void *user_data)
{
    g_panic.handler = handler;
    g_panic.user_data = user_data;
}

void panic(const char *fmt, ...)
{
    if (g_panic.panic_in_flight)
    {
        int exit_code = g_panic.exit_code != 0
            ? g_panic.exit_code
            : 1;
        exit(exit_code);
    }

    g_panic.panic_in_flight = true;

    char buffer[1024];

    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);

    LOG_FATAL("%s", buffer);

    if (g_panic.handler)
    {
        g_panic.handler(buffer, g_panic.user_data);
    }

    fflush(stdout);
    fflush(stderr);
    abort();
}

}
