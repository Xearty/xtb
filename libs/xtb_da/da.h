#ifndef _XTB_DA_H_
#define _XTB_DA_H_

#include <xtb_core/core.h>

#include <stddef.h>

#ifndef XTB_REALLOC
#include <stdlib.h>
#define XTB_REALLOC realloc
#endif /* XTB_REALLOC */

#ifndef XTB_FREE
#include <stdlib.h>
#define XTB_FREE free
#endif /* XTB_FREE */

// Initial capacity of a dynamic array
#ifndef XTB_DA_INIT_CAP
#define XTB_DA_INIT_CAP 256
#endif

#ifdef __cplusplus
#define XTB_DECLTYPE_CAST(T) (decltype(T))
#else
#define XTB_DECLTYPE_CAST(T)
#endif // __cplusplus

#define xtb_da_reserve(da, expected_capacity)                                              \
    do {                                                                                   \
        if ((expected_capacity) > (da)->capacity) {                                        \
            if ((da)->capacity == 0) {                                                     \
                (da)->capacity = XTB_DA_INIT_CAP;                                          \
            }                                                                              \
            while ((expected_capacity) > (da)->capacity) {                                 \
                (da)->capacity *= 2;                                                       \
            }                                                                              \
            (da)->items = XTB_DECLTYPE_CAST((da)->items)XTB_REALLOC((da)->items, (da)->capacity * sizeof(*(da)->items)); \
            XTB_ASSERT((da)->items != NULL && "Buy more RAM lol");                         \
        }                                                                                  \
    } while (0)

// Append an item to a dynamic array
#define xtb_da_append(da, item)                \
    do {                                       \
        xtb_da_reserve((da), (da)->count + 1); \
        (da)->items[(da)->count++] = (item);   \
    } while (0)

#define xtb_da_free(da) XTB_FREE((da).items)

// Append several items to a dynamic array
#define xtb_da_append_many(da, new_items, new_items_count)                                      \
    do {                                                                                        \
        xtb_da_reserve((da), (da)->count + (new_items_count));                                  \
        memcpy((da)->items + (da)->count, (new_items), (new_items_count)*sizeof(*(da)->items)); \
        (da)->count += (new_items_count);                                                       \
    } while (0)

#define xtb_da_resize(da, new_size)     \
    do {                                \
        xtb_da_reserve((da), new_size); \
        (da)->count = (new_size);       \
    } while (0)

#define xtb_da_last(da) (da)->items[(XTB_ASSERT((da)->count > 0), (da)->count-1)]

#define xtb_da_remove_unordered(da, i)               \
    do {                                             \
        size_t j = (i);                              \
        XTB_ASSERT(j < (da)->count);                 \
        (da)->items[j] = (da)->items[--(da)->count]; \
    } while(0)

// Foreach over Dynamic Arrays. Example:
// ```c
// typedef struct {
//     int *items;
//     size_t count;
//     size_t capacity;
// } Numbers;
//
// Numbers xs = {0};
//
// xtb_da_append(&xs, 69);
// xtb_da_append(&xs, 420);
// xtb_da_append(&xs, 1337);
//
// xtb_da_foreach(int, x, &xs) {
//     // `x` here is a pointer to the current element. You can get its index by taking a difference
//     // between `x` and the start of the array which is `x.items`.
//     size_t index = x - xs.items;
//     xtb_log(INFO, "%zu: %d", index, *x);
// }
// ```
#define xtb_da_foreach(Type, it, da) for (Type *it = (da)->items; it < (da)->items + (da)->count; ++it)

#define XTB_DA_DYNAMIC_ARRAY_FIELDS(ITEM_TYPE) \
    size_t count; \
    size_t capacity; \
    ITEM_TYPE* items;

#define XTB_DA_DEFINE_TYPE(TYPE_NAME, ITEM_TYPE) \
    typedef struct TYPE_NAME { XTB_DA_DYNAMIC_ARRAY_FIELDS(ITEM_TYPE) } TYPE_NAME

#endif // _XTB_DA_H_
