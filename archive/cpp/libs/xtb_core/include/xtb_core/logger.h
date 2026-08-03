#ifndef _XTB_LOGGER_H_
#define _XTB_LOGGER_H_

#include <xtb_core/context_cracking.h>

namespace xtb
{

enum LogLevel
{
    LOG_LEVEL_TRACE = 0,
    LOG_LEVEL_DEBUG,
    LOG_LEVEL_INFO,
    LOG_LEVEL_WARN,
    LOG_LEVEL_ERROR,
    LOG_LEVEL_FATAL,
};

using LogCallback = void(*)(LogLevel level, const char* message, void* user_data);

void logger_set_callback(LogCallback cb, void *user_data);
void logger_set_log_level(LogLevel log_level);
void logger_log(LogLevel level, const char *fmt, ...);

#define LOG_TRACE(fmt, ...) logger_log(LOG_LEVEL_TRACE, fmt, ##__VA_ARGS__)
#define LOG_DEBUG(fmt, ...) logger_log(LOG_LEVEL_DEBUG, fmt, ##__VA_ARGS__)
#define LOG_INFO(fmt, ...)  logger_log(LOG_LEVEL_INFO,  fmt, ##__VA_ARGS__)
#define LOG_WARN(fmt, ...)  logger_log(LOG_LEVEL_WARN,  fmt, ##__VA_ARGS__)
#define LOG_ERROR(fmt, ...) logger_log(LOG_LEVEL_ERROR, fmt, ##__VA_ARGS__)
#define LOG_FATAL(fmt, ...) logger_log(LOG_LEVEL_FATAL, fmt, ##__VA_ARGS__)

}

#endif // _XTB_LOGGER_H_
