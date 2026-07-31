#include <stddef.h>
#include <stdlib.h>

typedef void *(*Allocator)(
    void *allocator,
    size_t new_size,
    void *old_pointer,
    size_t old_size,
    size_t alignment
);

static void *c_allocator(
    void *allocator,
    size_t new_size,
    void *old_pointer,
    size_t old_size,
    size_t alignment
)
{
    (void)old_size;
    (void)alignment;
    if (allocator == NULL)
        return NULL;
    if (new_size == 0) {
        free(old_pointer);
        return NULL;
    }
    return realloc(old_pointer, new_size);
}

static Allocator allocator_slot = c_allocator;

Allocator *xtbd_test_c_allocator(void)
{
    return &allocator_slot;
}
