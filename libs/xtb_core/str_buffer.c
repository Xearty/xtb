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

static void buffer_ensure_capacity(XTB_String8_Buffer *str_buffer, size_t needed)
{
    if (str_buffer->capacity < needed)
    {
        size_t new_cap = XTB_GrowGeometric(str_buffer->size, needed);
        char *new_buffer = XTB_AllocateBytes(str_buffer->allocator, new_cap);

        // TODO: Add realloc to the allocator interface
        XTB_MemoryCopy(new_buffer, str_buffer->buffer, str_buffer->size);
        XTB_Deallocate(str_buffer->allocator, str_buffer->buffer);

        str_buffer->capacity = new_cap;
        str_buffer->buffer = new_buffer;
    }
}

void xtb_str8_buffer_push_back(XTB_String8_Buffer *str_buffer, XTB_String8 string)
{
    buffer_ensure_capacity(str_buffer, str_buffer->size + string.len);
    XTB_MemoryCopy(BufferAppendLocation(str_buffer), string.str, string.len);
    str_buffer->size += string.len;
}

void xtb_str8_buffer_push_front(XTB_String8_Buffer *str_buffer, XTB_String8 string)
{
    // TODO: This can be optimized. If we need to grow anyway, we can insert the old content
    // in the correct place and avoid shifting afterwards
    buffer_ensure_capacity(str_buffer, str_buffer->size + string.len);
    XTB_MemoryMove(str_buffer->buffer + string.len, str_buffer->buffer, str_buffer->size);
    XTB_MemoryCopy(str_buffer->buffer, string.str, string.len);
    str_buffer->size += string.len;
}

XTB_String8 xtb_str8_buffer_view(XTB_String8_Buffer *str_buffer)
{
    return xtb_str8(str_buffer->buffer, str_buffer->size);
}

XTB_String8 xtb_str8_buffer_detach(XTB_String8_Buffer *str_buffer)
{
    XTB_String8 str = xtb_str8(str_buffer->buffer, str_buffer->size);
    str_buffer->buffer = NULL;
    str_buffer->size = 0;
    str_buffer->capacity = 0;
    return str;
}

