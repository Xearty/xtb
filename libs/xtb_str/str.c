#include "str.h"

#include <string.h>

XTB_String8 xtb_str8(char *str, size_t len)
{
    return (XTB_String8){ str, len };
}

XTB_String8 xtb_str8_cstring(char *cstring)
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
