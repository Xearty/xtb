#ifndef _XTB_STR_BUFFER_H_
#define _XTB_STR_BUFFER_H_

#include <xtb_core/core.h>
#include <xtb_core/str.h>

#include <stddef.h>

XTB_C_LINKAGE_BEGIN

#define XTB_STR8_BUFFER_MIN_CAP 64

typedef struct XTB_String8_Buffer
{
    char *data;
    size_t size;
    size_t capacity;
    XTB_Allocator allocator;
} XTB_String8_Buffer;

XTB_String8_Buffer xtb_str8_buffer_new(XTB_Allocator allocator, size_t cap_hint);
XTB_String8_Buffer xtb_str8_buffer_from(XTB_Allocator allocator, XTB_String8 init);

void xtb_str8_buffer_push_back(XTB_String8_Buffer *str_buffer, XTB_String8 string);
#define xtb_str8_buffer_push_back_lit(str_buffer, lit) \
    xtb_str8_buffer_push_back((str_buffer), xtb_str8_lit(lit))
#define xtb_str8_buffer_push_back_cstring(str_buffer, cstring) \
    xtb_str8_buffer_push_back((str_buffer), xtb_str8_cstring(cstring))

void xtb_str8_buffer_push_front(XTB_String8_Buffer *str_buffer, XTB_String8 string);
#define xtb_str8_buffer_push_front_lit(str_buffer, lit) \
    xtb_str8_buffer_push_front((str_buffer), xtb_str8_lit(lit))
#define xtb_str8_buffer_push_front_cstring(str_buffer, cstring) \
    xtb_str8_buffer_push_front((str_buffer), xtb_str8_cstring(cstring))

XTB_String8 xtb_str8_buffer_view(XTB_String8_Buffer *str_buffer);
#define xtb_str8_buffer_view_copy(allocator, str_buffer) \
    xtb_str8_copy((allocator), xtb_str8_buffer_view((str_buffer)))

XTB_String8 xtb_str8_buffer_detach(XTB_String8_Buffer *str_buffer);

XTB_C_LINKAGE_END

#endif // _XTB_STR_BUFFER_H_
