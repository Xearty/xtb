#include <xtb_core/core.h>
#include <xtb_core/str_buffer.h>
#include <xtb_core/contract.h>

#include <string.h>

#define RemainingCapacity(str_buffer) ((str_buffer)->capacity - (str_buffer)->size)
#define BufferAppendLocation(str_buffer) ((str_buffer->data) + (str_buffer)->size)
#define AssertOwnsMemory(str_buffer) Assert((str_buffer)->data != NULL)

StringBuffer str_buffer_new(Allocator* allocator, size_t cap_hint)
{
    StringBuffer str_buffer;
    str_buffer.allocator = allocator;
    str_buffer.size = 0;
    str_buffer.capacity = Max(cap_hint, STR_BUFFER_MIN_CAP);
    str_buffer.data = AllocateBytes(allocator, str_buffer.capacity);
    return str_buffer;
}

static void buffer_ensure_capacity(StringBuffer *str_buffer, size_t needed)
{
    AssertOwnsMemory(str_buffer);

    if (str_buffer->capacity < needed)
    {
        size_t new_cap = GrowGeometric(str_buffer->size, needed);
        u8 *new_buffer = AllocateBytes(str_buffer->allocator, new_cap);

        // TODO: Add realloc to the allocator interface
        MemoryCopy(new_buffer, str_buffer->data, str_buffer->size);
        Deallocate(str_buffer->allocator, str_buffer->data);

        str_buffer->capacity = new_cap;
        str_buffer->data = new_buffer;
    }
}

void str_buffer_push_back(StringBuffer *str_buffer, String string)
{
    AssertOwnsMemory(str_buffer);

    buffer_ensure_capacity(str_buffer, str_buffer->size + string.len);
    MemoryCopy(BufferAppendLocation(str_buffer), string.str, string.len);
    str_buffer->size += string.len;
}

void str_buffer_push_front(StringBuffer *str_buffer, String string)
{
    AssertOwnsMemory(str_buffer);

    // TODO: This can be optimized. If we need to grow anyway, we can insert the old content
    // in the correct place and avoid shifting afterwards
    buffer_ensure_capacity(str_buffer, str_buffer->size + string.len);
    MemoryMove(str_buffer->data + string.len, str_buffer->data, str_buffer->size);
    MemoryCopy(str_buffer->data, string.str, string.len);
    str_buffer->size += string.len;
}

String str_buffer_view(StringBuffer *str_buffer)
{
    AssertOwnsMemory(str_buffer);

    return str_from(str_buffer->data, str_buffer->size);
}

String str_buffer_detach(StringBuffer *str_buffer)
{
    AssertOwnsMemory(str_buffer);

    String string = str_from(str_buffer->data, str_buffer->size);
    str_buffer->data = NULL;
    str_buffer->size = 0;
    str_buffer->capacity = 0;
    return string;
}

