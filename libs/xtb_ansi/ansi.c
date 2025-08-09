#include "ansi.h"
#include <stdarg.h>

#define DEF_PRINT_COLOR_FUNC(COLOR, ANSI_CODE)                       \
    void xtb_ansi_print_##COLOR(FILE *stream, const char *fmt, ...) \
    {                                                                \
        va_list args;                                                \
        va_start(args, fmt);                                         \
        fprintf(stream, ANSI_CODE);                                  \
        vfprintf(stream, fmt, args);                                 \
        fprintf(stream, COLOR_RESET);                                \
        va_end(args);                                                \
    }

ANSI_COLOR_LIST(DEF_PRINT_COLOR_FUNC)

#undef DEF_PRINT_COLOR_FUNC
