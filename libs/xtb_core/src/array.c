#include "xtb_core/core.h"
#include <xtb_core/array.h>

#include <stdlib.h>
#include <string.h>

static bool generic_array_is_consistent(Generic_Array gen)
{
    bool is_capacity_correct = 0 <= gen.array->capacity;
    bool is_size_correct = (0 <= gen.array->count && gen.array->count <= gen.array->capacity);
    if (gen.array->capacity > 0)
    {
        is_capacity_correct = is_capacity_correct && gen.array->allocator != NULL;
    }

    bool is_data_correct = (gen.array->data == NULL) == (gen.array->capacity == 0);
    bool item_size_correct = gen.item_size > 0;
    bool alignment_correct = ((gen.item_align & (gen.item_align - 1)) == 0) && gen.item_align > 0; // if is power of two and bigger than zero
    bool result = is_capacity_correct && is_size_correct && is_data_correct && item_size_correct && alignment_correct;
    XTB_ASSERT(result);
    return result;
}

void generic_array_init(Generic_Array gen, Allocator *allocator)
{
    generic_array_deinit(gen);
    gen.array->allocator = allocator;
    XTB_ASSERT(generic_array_is_consistent(gen));
}

void generic_array_deinit(Generic_Array gen)
{
    XTB_ASSERT(generic_array_is_consistent(gen));
    if (gen.array->capacity > 0)
    {
        (*gen.array->allocator)(gen.array->allocator, 0, gen.array->data, gen.array->capacity *gen.item_size, gen.item_align);
    }
    memset(gen.array, 0, sizeof *gen.array);
}

void generic_array_set_capacity(Generic_Array gen, isize capacity)
{
    XTB_ASSERT(generic_array_is_consistent(gen));
    XTB_ASSERT(capacity >= 0 && gen.array->allocator != NULL);

    isize old_byte_size = gen.item_size * gen.array->capacity;
    isize new_byte_size = gen.item_size * capacity;
    gen.array->data = (uint8_t *)(*gen.array->allocator)(gen.array->allocator, new_byte_size, gen.array->data, old_byte_size, gen.item_align);

    // trim the size if too big
    gen.array->capacity = capacity;
    if (gen.array->count > gen.array->capacity)
    {
        gen.array->count = gen.array->capacity;
    }

    XTB_ASSERT(generic_array_is_consistent(gen));
}

void generic_array_resize(Generic_Array gen, isize to_size, bool zero_new)
{
    generic_array_reserve(gen, to_size);
    if (zero_new && to_size > gen.array->count)
    {
        memset(gen.array->data + gen.array->count * gen.item_size, 0, (size_t)((to_size - gen.array->count) * gen.item_size));
    }

    gen.array->count = to_size;
    XTB_ASSERT(generic_array_is_consistent(gen));
}

void generic_array_reserve(Generic_Array gen, isize to_fit)
{
    XTB_ASSERT(generic_array_is_consistent(gen));
    if (gen.array->capacity > to_fit) return;

    isize new_capacity = to_fit;
    isize growth_step = gen.array->capacity * 3 / 2 + 8;
    if (new_capacity < growth_step)
        new_capacity = growth_step;

    generic_array_set_capacity(gen, new_capacity + 1);
}

void generic_array_append(Generic_Array gen, const void *data, isize data_count)
{
    XTB_ASSERT(data_count >= 0 && (data || data_count == 0));
    generic_array_reserve(gen, gen.array->count + data_count);
    memcpy(gen.array->data + gen.item_size * gen.array->count, data, (size_t)(gen.item_size * data_count));
    gen.array->count += data_count;
    XTB_ASSERT(generic_array_is_consistent(gen));
}
