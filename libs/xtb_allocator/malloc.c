#include "malloc.h"
#include <stdlib.h>

static void *xtb_allocator_malloc_stub(void *context, size_t size)
{
    (void)context;
    return malloc(size);
}

static void xtb_allocator_free_stub(void *context, void *ptr)
{
    (void)context;
    free(ptr);
}

XTB_Allocator xtb_malloc_allocator()
{
    XTB_Allocator allocator = {};
    allocator.allocate = xtb_allocator_malloc_stub;
    allocator.deallocate = xtb_allocator_free_stub;
    return allocator;
}

