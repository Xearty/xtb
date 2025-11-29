#ifndef XTB_CORE_ALLOCATOR_INTERFACE_H
#define XTB_CORE_ALLOCATOR_INTERFACE_H

#include <xtb_core/core.h>
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

namespace xtb
{

using Allocator = void*(*)(void* alloc, int64_t new_size, void* old_ptr, int64_t old_size, int64_t align);

void allocator_deallocate(Allocator* alloc, void* old_ptr, int64_t old_size, int64_t align);
void* allocator_allocate(Allocator* alloc, int64_t new_size, int64_t align);
void* allocator_reallocate(Allocator* alloc, int64_t new_size, void* old_ptr, int64_t old_size, int64_t align);
void* allocator_try_reallocate(Allocator* alloc, int64_t new_size, void* old_ptr, int64_t old_size, int64_t align);

struct AllocatorSet
{
    Allocator *heap_allocator;
    Allocator *static_allocator;
};

Allocator *allocator_get_heap(void);
Allocator *allocator_get_static(void);

AllocatorSet allocator_set_heap(Allocator *allocator);
AllocatorSet allocator_set_static(Allocator *allocator);

void allocators_init();

template <typename T>
inline T* xtb_allocate_array_value_init(void *alloc, isize count)
{
    T* ptr = (T*) allocator_allocate((Allocator*)alloc, count * (int64_t)sizeof(T), __alignof(T));
    for (isize i = 0; i < count; ++i)
    {
        ptr[i] = T{};
    }
    return ptr;
}

template <typename T>
inline T* xtb_allocate_value_init(void* alloc)
{
    return xtb_allocate_array_value_init<T>(alloc, 1);
}

#define AllocateArray(alloc, new_count, T) (T*)  allocator_allocate((alloc), (new_count)*sizeof(T), __alignof(T))
#define AllocateBytes(alloc, new_count)          AllocateArray(alloc, new_count, u8)
#define Allocate(alloc, T)                       AllocateArray(alloc, 1, T)
#define Reallocate(alloc, old_ptr, old_size, new_size)    allocator_reallocate((alloc), (new_size), (old_ptr), (old_size), __alignof(T))
#define ReallocateTyped(alloc, old_ptr, old_size, new_size, T)    (T*)Reallocate(alloc, old_ptr, (old_size)*sizeof(T), (new_size)*sizeof(T))
#define Deallocate(alloc, old_ptr)               allocator_deallocate((alloc), (old_ptr), (1)*sizeof(char), __alignof(char))

// #define AllocateArrayZero(alloc, new_count, T)   (T*)MemoryZeroTyped(AllocateArray(alloc, new_count, T), new_count)
// #define AllocateBytesZero(alloc, new_count)      (u8*)AllocateArrayZero(alloc, new_count, char)
// #define AllocateZero(alloc, T)                   (T*)AllocateArrayZero(alloc, 1, T)

#define AllocateArrayZero(alloc, new_count, T) \
    xtb_allocate_array_value_init<T>((alloc), (new_count))

#define AllocateZero(alloc, T) \
    xtb_allocate_value_init<T>((alloc))

#define AllocateBytesZero(alloc, new_count) \
    (u8*)xtb_allocate_array_value_init<unsigned char>((alloc), (new_count))

}

#endif // XTB_CORE_ALLOCATOR_INTERFACE_H
