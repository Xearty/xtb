#include <xtb_core/panic.h>
#include <xtb_core/logger.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct Panic
{
    PanicHandler handler;
    void *user_data;
} Panic;

Panic g_panic;

void panic_handler_set_handler(PanicHandler handler, void *user_data)
{
    g_panic.handler = handler;
    g_panic.user_data = user_data;
}

void panic(const char *fmt, ...)
{
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
