#ifndef _XTB_STR_H_
#define _XTB_STR_H_

#include <xtb_core/core.h>
#include <stddef.h>
#include <stdbool.h>

typedef struct XTB_String8
{
    char *str;
    size_t len;
} XTB_String8;

XTB_String8 xtb_str8(const char *str, size_t len);
XTB_String8 xtb_str8_cstring(const char *cstring);
XTB_String8 xtb_str8_copy(XTB_Allocator allocator, XTB_String8 string);
void xtb_str8_free(XTB_Allocator allocator, XTB_String8 str);
bool xtb_str8_is_invalid(XTB_String8 string);
bool xtb_str8_is_valid(XTB_String8 string);

#define xtb_str8_lit(cstring_literal) \
    (XTB_String8){ cstring_literal, sizeof(cstring_literal) - 1 }

#define xtb_str8_copy_lit(allocator, cstring_literal) \
    xtb_str8_copy(allocator, xtb_str8_lit(cstring_literal))

#define xtb_str8_invalid xtb_str8(NULL, 0)

#endif // _XTB_STR_H_
