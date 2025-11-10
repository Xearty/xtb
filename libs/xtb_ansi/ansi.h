#ifndef _XTB_ANSI_H_
#define _XTB_ANSI_H_

#include "escape_codes.h"
#include <stdio.h>
#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ANSI_COLOR_LIST(MACRO)              \
    MACRO(black, BLK)                       \
    MACRO(red, RED)                         \
    MACRO(green, GRN)                       \
    MACRO(yellow, YEL)                      \
    MACRO(blue, BLU)                        \
    MACRO(magenta, MAG)                     \
    MACRO(cyan, CYN)                        \
    MACRO(white, WHT)                       \
                                            \
    MACRO(bold_black, BBLK)                 \
    MACRO(bold_red, BRED)                   \
    MACRO(bold_green, BGRN)                 \
    MACRO(bold_yellow, BYEL)                \
    MACRO(bold_blue, BBLU)                  \
    MACRO(bold_magenta, BMAG)               \
    MACRO(bold_cyan, BCYN)                  \
    MACRO(bold_white, BWHT)                 \
                                            \
    MACRO(underlined_black, UBLK)           \
    MACRO(underlined_red, URED)             \
    MACRO(underlined_green, UGRN)           \
    MACRO(underlined_yellow, UYEL)          \
    MACRO(underlined_blue, UBLU)            \
    MACRO(underlined_magenta, UMAG)         \
    MACRO(underlined_cyan, UCYN)            \
    MACRO(underlined_white, UWHT)           \
                                            \
    MACRO(black_background, BLKB)           \
    MACRO(red_background, REDB)             \
    MACRO(green_background, GRNB)           \
    MACRO(yellow_background, YELB)          \
    MACRO(blue_background, BLUB)            \
    MACRO(magenta_background, MAGB)         \
    MACRO(cyan_background, CYNB)            \
    MACRO(white_background, WHTB)           \
                                            \
    MACRO(bright_black_background, BLKHB)   \
    MACRO(bright_red_background, REDHB)     \
    MACRO(bright_green_background, GRNHB)   \
    MACRO(bright_yellow_background, YELHB)  \
    MACRO(bright_blue_background, BLUHB)    \
    MACRO(bright_magenta_background, MAGHB) \
    MACRO(bright_cyan_background, CYNHB)    \
    MACRO(bright_white_background, WHTHB)   \
                                            \
    MACRO(bright_black, HBLK)               \
    MACRO(bright_red, HRED)                 \
    MACRO(bright_green, HGRN)               \
    MACRO(bright_yellow, HYEL)              \
    MACRO(bright_blue, HBLU)                \
    MACRO(bright_magenta, HMAG)             \
    MACRO(bright_cyan, HCYN)                \
    MACRO(bright_white, HWHT)               \
                                            \
    MACRO(bold_bright_black, BHBLK)         \
    MACRO(bold_bright_red, BHRED)           \
    MACRO(bold_bright_green, BHGRN)         \
    MACRO(bold_bright_yellow, BHYEL)        \
    MACRO(bold_bright_blue, BHBLU)          \
    MACRO(bold_bright_magenta, BHMAG)       \
    MACRO(bold_bright_cyan, BHCYN)          \
    MACRO(bold_bright_white, BHWHT)

#define DEC_PRINT_COLOR_FUNC(COLOR, ANSI_CODE) \
    void ansi_print_##COLOR(FILE *stream, const char *fmt, ...);

ANSI_COLOR_LIST(DEC_PRINT_COLOR_FUNC);

void ansi_print_style(FILE *stream, const char *ansi_seq, const char *fmt, ...);
void ansi_vprint_style(FILE *stream, const char *ansi_seq, const char *fmt, va_list va_args);

#undef DEC_PRINT_COLOR_FUNC

#ifdef __cplusplus
}
#endif

#endif // _XTB_ANSI_H_
