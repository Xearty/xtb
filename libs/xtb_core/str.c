#include "str.h"

#include <string.h>

XTB_String8 xtb_str8(const char *str, size_t len)
{
    return (XTB_String8){ (char*)str, len };
}

XTB_String8 xtb_str8_cstring(const char *cstring)
{
    size_t len = strlen(cstring);
    return xtb_str8(cstring, len);
}

XTB_String8 xtb_str8_copy(XTB_Allocator allocator, XTB_String8 string)
{
    char *buf = XTB_AllocateArray(allocator, char, string.len + 1);
    strncpy(buf, string.str, string.len)[string.len] = '\0';
    return xtb_str8(buf, string.len);
}

void xtb_str8_free(XTB_Allocator allocator, XTB_String8 str)
{
    XTB_Deallocate(allocator, str.str);
}

bool xtb_str8_is_invalid(XTB_String8 string)
{
    return string.str == NULL;
}

bool xtb_str8_is_valid(XTB_String8 string)
{
    return !xtb_str8_is_invalid(string);
}

