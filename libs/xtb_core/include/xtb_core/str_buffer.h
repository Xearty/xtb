#ifndef _XTB_STR_BUFFER_H_
#define _XTB_STR_BUFFER_H_

#include <xtb_core/core.h>
#include <xtb_core/str.h>

#include <stddef.h>

C_LINKAGE_BEGIN

#define STR_BUFFER_MIN_CAP 64

typedef struct StringBuffer
{
    Allocator* allocator;
    char *data;
    size_t size;
    size_t capacity;
} StringBuffer;

StringBuffer str_buffer_new(Allocator* allocator, size_t cap_hint);
StringBuffer str_buffer_from(Allocator* allocator, String init);

void str_buffer_push_back(StringBuffer *str_buffer, String string);
#define str_buffer_push_back_lit(str_buffer, lit) \
    str_buffer_push_back((str_buffer), str(lit))
#define str_buffer_push_back_cstring(str_buffer, cstring) \
    str_buffer_push_back((str_buffer), cstr(cstring))

void str_buffer_push_front(StringBuffer *str_buffer, String string);
#define str_buffer_push_front_lit(str_buffer, lit) \
    str_buffer_push_front((str_buffer), str(lit))
#define str_buffer_push_front_cstring(str_buffer, cstring) \
    str_buffer_push_front((str_buffer), cstr(cstring))

String str_buffer_view(StringBuffer *str_buffer);
#define str_buffer_view_copy(allocator, str_buffer) \
    str_copy((allocator), str_buffer_view((str_buffer)))

String str_buffer_detach(StringBuffer *str_buffer);

C_LINKAGE_END

#endif // _XTB_STR_BUFFER_H_
