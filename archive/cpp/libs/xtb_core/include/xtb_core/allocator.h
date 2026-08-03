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
T* allocate_array(Allocator* allocator, isize count)
{
    return (T*)allocator_allocate(allocator, count * sizeof(T), __alignof(T));
}

template <typename T>
T* allocate(Allocator* allocator)
{
    return allocate_array<T>(allocator, 1);
}

inline u8* allocate_bytes(Allocator* allocator, isize count)
{
    return allocate_array<u8>(allocator, count);
}

template <typename T>
inline T* allocate_array_value_init(Allocator *allocator, isize count)
{
    T* buf = allocate_array<T>(allocator, count);
    for (isize i = 0; i < count; ++i)
    {
        buf[i] = T{};
    }
    return buf;
}

template <typename T>
inline T* allocate_value_init(Allocator* allocator)
{
    return allocate_array_value_init<T>(allocator, 1);
}

template <typename T>
void deallocate(Allocator* allocator, T* ptr)
{
    allocator_deallocate(allocator, ptr, 1, __alignof(T));
}

template <typename T>
T* reallocate(Allocator* allocator, void* old_ptr, isize old_size, isize new_size)
{
    return (T*)allocator_reallocate(allocator, new_size * sizeof(T), old_ptr, old_size * sizeof(T), __alignof(T));
}

inline u8* reallocate_bytes(Allocator* allocator, void* old_ptr, isize old_size, isize new_size)
{
    return reallocate<u8>(allocator, old_ptr, old_size, new_size);
}

}

#endif // XTB_CORE_ALLOCATOR_INTERFACE_H
