#include "str_buffer.h"

#include "core.h"

#include <string.h>

#define RemainingCapacity(str_buffer) ((str_buffer)->capacity - (str_buffer)->size)
#define BufferAppendLocation(str_buffer) ((str_buffer->buffer) + (str_buffer)->size)

XTB_String8_Buffer xtb_str8_buffer_new(XTB_Allocator allocator, size_t cap_hint)
{
    XTB_String8_Buffer str_buffer;
    str_buffer.allocator = allocator;
    str_buffer.size = 0;
    str_buffer.capacity = XTB_Max(cap_hint, XTB_STR8_BUFFER_MIN_CAP);
    str_buffer.buffer = XTB_AllocateBytes(allocator, str_buffer.capacity);
    return str_buffer;
}

void xtb_str8_buffer_push_back(XTB_String8_Buffer *str_buffer, XTB_String8 string)
{
    if (RemainingCapacity(str_buffer) < string.len)
    {
        // need to grow
        size_t needed = str_buffer->size + string.len;
        size_t new_cap = XTB_GrowGeometric(str_buffer->size, needed);
        char *new_buffer = XTB_AllocateBytes(str_buffer->allocator, new_cap);

        // TODO: Add realloc to the allocator interface
        XTB_MemoryCopy(new_buffer, str_buffer->buffer, str_buffer->size);
        XTB_Deallocate(str_buffer->allocator, str_buffer->buffer);

        str_buffer->capacity = new_cap;
        str_buffer->buffer = new_buffer;
    }

    XTB_MemoryCopy(BufferAppendLocation(str_buffer), string.str, string.len);
    str_buffer->size += string.len;
}

XTB_String8 xtb_str8_buffer_view(XTB_String8_Buffer *str_buffer)
{
    return xtb_str8(str_buffer->buffer, str_buffer->size);
}

