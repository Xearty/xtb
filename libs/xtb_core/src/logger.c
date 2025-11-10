#include <xtb_core/logger.h>
#include <xtb_ansi/ansi.h>

typedef struct Logger
{
    LogCallback cb;
    void *user_data;
    LogLevel level_filter_threshold;
} Logger;

Logger g_logger;

void logger_set_callback(LogCallback cb, void *user_data)
{
    g_logger.cb = cb;
    g_logger.user_data = user_data;
}

void logger_set_log_level(int log_level)
{
    g_logger.level_filter_threshold = log_level;
}

void logger_log(LogLevel level, const char *fmt, ...)
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
