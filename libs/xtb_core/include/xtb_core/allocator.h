#ifndef XTB_CORE_ALLOCATOR_INTERFACE_H
#define XTB_CORE_ALLOCATOR_INTERFACE_H

#include <xtb_core/core.h>
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

C_LINKAGE_BEGIN

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

#define AllocateArray(alloc, new_count, T) (T*)  allocator_allocate((alloc), (new_count)*sizeof(T), __alignof(T))
#define AllocateBytes(alloc, new_count)          AllocateArray(alloc, new_count, u8)
#define Allocate(alloc, T)                       AllocateArray(alloc, 1, T)
#define Deallocate(alloc, old_ptr)               allocator_deallocate((alloc), (old_ptr), (1)*sizeof(char), __alignof(char))

#define AllocateArrayZero(alloc, new_count, T)   MemoryZeroTyped(AllocateArray(alloc, new_count, T), new_count)
#define AllocateBytesZero(alloc, new_count)      AllocateArrayZero(alloc, new_count, char)
#define AllocateZero(alloc, T)                   AllocateArrayZero(alloc, 1, T)

#ifdef ALLOCATOR_SHORTHANDS

#define AllocateArray AllocateArray
#define AllocateBytes AllocateBytes
#define Allocate Allocate
#define Deallocate Deallocate
#define AllocateArrayZero AllocateArrayZero
#define AllocateBytesZero AllocateBytesZero
#define AllocateZero AllocateZero
#endif

C_LINKAGE_END

#endif // XTB_CORE_ALLOCATOR_INTERFACE_H
