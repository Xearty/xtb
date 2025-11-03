#ifndef XTB_CORE_ALLOCATOR_INTERFACE_H
#define XTB_CORE_ALLOCATOR_INTERFACE_H

#include <stddef.h>

/****************************************************************
  Allocator Interface
****************************************************************/
typedef void*(*XTB_Allocate_Fn)(void*, size_t);
typedef void(*XTB_Deallocate_Fn)(void*, void*);

typedef struct XTB_Allocator
{
    void *context;
    XTB_Allocate_Fn allocate;
    XTB_Deallocate_Fn deallocate;
} XTB_Allocator;

#define XTB_AllocateArray(allocator, type, count) (type*)(allocator.allocate(allocator.context, sizeof(type) * (count)))
#define XTB_AllocateBytes(allocator, count) XTB_AllocateArray(allocator, char, count)
#define XTB_Allocate(allocator, type) XTB_AllocateArray(allocator, type, 1)
#define XTB_Deallocate(allocator, ptr) allocator.deallocate(allocator.context, ptr)

#endif // XTB_CORE_ALLOCATOR_INTERFACE_H
