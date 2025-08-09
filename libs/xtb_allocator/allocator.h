#ifndef _XTB_ALLOCATOR_H_
#define _XTB_ALLOCATOR_H_

#include <stddef.h>

typedef void*(*XTB_Allocate)(void*, size_t);
typedef void(*XTB_Deallocate)(void*, void*);

typedef struct XTB_Allocator XTB_Allocator;
struct XTB_Allocator
{
    void *context;
    XTB_Allocate allocate;
    XTB_Deallocate deallocate;
};

#ifdef XTB_ALLOCATOR_MALLOC_IMPLEMENTATION
#include <stdlib.h>
void *xtb_allocator_malloc_stub(void *context, size_t size)
{
    (void)context;
    return malloc(size);
}

void xtb_allocator_free_stub(void *context, void *ptr)
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
#endif

#endif // _XTB_ALLOCATOR_H_
