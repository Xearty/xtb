#ifndef XTB_CORE_ALLOCATOR_INTERFACE_H
#define XTB_CORE_ALLOCATOR_INTERFACE_H

#include <xtb_core/core.h>
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

XTB_C_LINKAGE_BEGIN

typedef void* (*Allocator)(void* alloc, int64_t new_size, void* old_ptr, int64_t old_size, int64_t align);

void allocator_deallocate(Allocator* alloc, void* old_ptr, int64_t old_size, int64_t align);
void* allocator_allocate(Allocator* alloc, int64_t new_size, int64_t align);
void* allocator_reallocate(Allocator* alloc, int64_t new_size, void* old_ptr, int64_t old_size, int64_t align);
void* allocator_try_reallocate(Allocator* alloc, int64_t new_size, void* old_ptr, int64_t old_size, int64_t align);

typedef struct Allocator_Set
{
    Allocator *heap_allocator;
    Allocator *static_allocator;
} Allocator_Set;

Allocator *allocator_get_heap(void);
Allocator *allocator_get_static(void);

Allocator_Set allocator_set_heap(Allocator *allocator);
Allocator_Set allocator_set_static(Allocator *allocator);

void allocators_init();

#define XTB_AllocateArray(alloc, new_count, T) (T*)  allocator_allocate((alloc), (new_count)*sizeof(T), __alignof(T))
#define XTB_AllocateBytes(alloc, new_count)          XTB_AllocateArray(alloc, new_count, char)
#define XTB_Allocate(alloc, T)                       XTB_AllocateArray(alloc, 1, T)
#define XTB_Deallocate(alloc, old_ptr)               allocator_deallocate((alloc), (old_ptr), (1)*sizeof(char), __alignof(char))

#define XTB_AllocateArrayZero(alloc, new_count, T)   XTB_MemoryZeroTyped(XTB_AllocateArray(alloc, new_count, T), new_count)
#define XTB_AllocateBytesZero(alloc, new_count)      XTB_AllocateArrayZero(alloc, new_count, char)
#define XTB_AllocateZero(alloc, T)                   XTB_AllocateArrayZero(alloc, 1, T)

#ifdef XTB_ALLOCATOR_SHORTHANDS

#define AllocateArray XTB_AllocateArray
#define AllocateBytes XTB_AllocateBytes
#define Allocate XTB_Allocate
#define Deallocate XTB_Deallocate
#define AllocateArrayZero XTB_AllocateArrayZero
#define AllocateBytesZero XTB_AllocateBytesZero
#define AllocateZero XTB_AllocateZero
#endif

XTB_C_LINKAGE_END

#endif // XTB_CORE_ALLOCATOR_INTERFACE_H
