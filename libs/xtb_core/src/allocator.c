#include <xtb_core/allocator.h>
#include <xtb_core/contract.h>
#include <string.h>
#include <stdlib.h>

Allocator_Set g_allocators;

Allocator g_malloc_allocator;

static bool is_power_of_two_or_zero(int64_t num)
{
    uint64_t n = (uint64_t)num;
    return ((n & (n - 1)) == 0);
}

static bool is_power_of_two(int64_t num)
{
    return (num > 0 && is_power_of_two_or_zero(num));
}

static void* malloc_allocate(int64_t new_size, void* old_ptr, int64_t old_size, int64_t align)
{
    ASSERT(new_size >= 0 && old_size >= 0 && align >= 0);

    void* new_ptr = NULL;

    if (new_size == 0)
    {
        free(old_ptr);
    }
    else if (align <= 16)
    {
        new_ptr = realloc(old_ptr, (size_t) new_size);
    }
    else
    {
        int64_t min_size = Min(new_size, old_size);
        new_ptr = aligned_alloc((size_t)align, (size_t)new_size);
        if (new_ptr != 0)
        {
            memcpy(new_ptr, old_ptr, min_size);
            free(old_ptr);
        }
    }

    return new_ptr;
}

static void* malloc_allocator_procedure(void* alloc, int64_t new_size, void* old_ptr, int64_t old_size, int64_t align)
{
    Unused(alloc);
    void* new_ptr = malloc_allocate(new_size, old_ptr, old_size, align);
    return new_ptr;
}

static void init_allocator_set(void)
{
    g_allocators.heap_allocator = &g_malloc_allocator;
    g_allocators.static_allocator = &g_malloc_allocator;
}

void allocators_init(void)
{
    g_malloc_allocator = malloc_allocator_procedure;
    init_allocator_set();
}

Allocator *allocator_get_heap(void)
{
    return g_allocators.heap_allocator;
}

Allocator *allocator_get_static(void)
{
    return g_allocators.static_allocator;
}

Allocator_Set allocator_set_heap(Allocator *allocator)
{
    Allocator_Set prev_allocators = g_allocators;
    g_allocators.heap_allocator = allocator;
    return prev_allocators;
}

Allocator_Set allocator_set_static(Allocator *allocator)
{
    Allocator_Set prev_allocators = g_allocators;
    g_allocators.static_allocator = allocator;
    return prev_allocators;
}

void* allocator_try_reallocate(Allocator* alloc, int64_t new_size, void* old_ptr, int64_t old_size, int64_t align)
{
    ASSERT(alloc != NULL && new_size >= 0 && old_size >= 0 && is_power_of_two(align));
    void* out = (*alloc)(alloc, new_size, old_ptr, old_size, align);
    return out;
}

void* allocator_reallocate(Allocator* alloc, int64_t new_size, void* old_ptr, int64_t old_size, int64_t align)
{
    return allocator_try_reallocate(alloc, new_size, old_ptr, old_size, align);
}

void* allocator_allocate(Allocator* alloc, int64_t new_size, int64_t align)
{
    return allocator_try_reallocate(alloc, new_size, NULL, 0, align);
}

void allocator_deallocate(Allocator* alloc, void* old_ptr, int64_t old_size, int64_t align)
{
    if(old_size > 0)
    {
        (*alloc)(alloc, 0, old_ptr, old_size, align);
    }
}

