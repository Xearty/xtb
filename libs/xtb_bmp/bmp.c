#include "bmp.h"

#include <stdio.h>
#include <assert.h>
#include <stdbool.h>
#include <string.h>
#include <stdint.h>

#define internal static
#define NOT_IMPLEMENTED do assert(0 && "NOT IMPLEMENTED"); while (0)

#include "utils.c"
#include "measure.c"

#include "prepass.c"
#include "bitfields.c"
#include "pixel_data.c"

#include "allocator.c"

#define XTB_BMP_COLOR_TABLE_OFFSET 0x36
#include "bitmap.c"
#include "dib.c"

#include "write.c"

XTB_BMP_Color
xtb_bmp_color_create(XTB_Byte b, XTB_Byte g, XTB_Byte r, XTB_Byte a)
{
    XTB_BMP_Color color;
    color.b = b;
    color.g = g;
    color.r = r;
    color.a = a;

    return color;
}
