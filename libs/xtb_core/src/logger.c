#include <xtb_core/logger.h>
#include <xtb_ansi/ansi.h>

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
        ansi_print_style(stderr, level_style[level], "[%s] %s", level_str[level], buffer);
        fputs("\n", stderr);
    }
}
