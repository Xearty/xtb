#include "ansi.h"
#include <stdarg.h>
#include "colors_8bit.h"

void ansi_vprint_style(FILE *stream, const char *ansi_seq, const char *fmt, va_list va_args)
{
    fputs(ansi_seq, stream);
    vfprintf(stream, fmt, va_args);
    fputs(COLOR_RESET, stream);
}

void ansi_print_style(FILE *stream, const char *ansi_seq, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    ansi_vprint_style(stream, ansi_seq, fmt, args);
    va_end(args);
}

#define DEF_PRINT_COLOR_FUNC(COLOR, ANSI_CODE)                      \
    void ansi_print_##COLOR(FILE *stream, const char *fmt, ...) \
    {                                                               \
        va_list args;                                               \
        va_start(args, fmt);                                        \
        ansi_vprint_style(stream, ANSI_CODE, fmt, args);        \
        va_end(args);                                               \
    }

ANSI_COLOR_LIST(DEF_PRINT_COLOR_FUNC)

const char* ansi_color8_foreground(int index)
{
    return ansi_foreground_colors_8bit[index];
}

const char* ansi_color8_background(int index)
{
    return ansi_background_colors_8bit[index];
}

#undef DEF_PRINT_COLOR_FUNC
