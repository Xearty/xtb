#include <xtb_core/panic.h>
#include <xtb_core/logger.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

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
