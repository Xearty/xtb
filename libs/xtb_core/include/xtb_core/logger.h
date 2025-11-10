#ifndef _XTB_LOGGER_H_
#define _XTB_LOGGER_H_

#include <xtb_core/context_cracking.h>

C_LINKAGE_BEGIN

typedef enum XTB_Log_Level
{
    XTB_LOG_TRACE = 0,
    XTB_LOG_DEBUG,
    XTB_LOG_INFO,
    XTB_LOG_WARN,
    XTB_LOG_ERROR,
    XTB_LOG_FATAL,
} XTB_Log_Level;

typedef void (*XTB_Log_Callback)(XTB_Log_Level level, const char *message, void *user_data);

void xtb_set_log_callback(XTB_Log_Callback cb, void *user_data);
void xtb_set_trace_log_level(int log_level);
void xtb_log(XTB_Log_Level level, const char *fmt, ...);

#define XTB_LOG_TRACE(fmt, ...) xtb_log(XTB_LOG_TRACE, fmt, ##__VA_ARGS__)
#define XTB_LOG_DEBUG(fmt, ...) xtb_log(XTB_LOG_DEBUG, fmt, ##__VA_ARGS__)
#define XTB_LOG_INFO(fmt, ...)  xtb_log(XTB_LOG_INFO,  fmt, ##__VA_ARGS__)
#define XTB_LOG_WARN(fmt, ...)  xtb_log(XTB_LOG_WARN,  fmt, ##__VA_ARGS__)
#define XTB_LOG_ERROR(fmt, ...) xtb_log(XTB_LOG_ERROR, fmt, ##__VA_ARGS__)
#define XTB_LOG_FATAL(fmt, ...) xtb_log(XTB_LOG_FATAL, fmt, ##__VA_ARGS__)

C_LINKAGE_END

#endif // _XTB_LOGGER_H_
