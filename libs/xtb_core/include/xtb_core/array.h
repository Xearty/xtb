#ifndef _XTB_ARRAY_H_
#define _XTB_ARRAY_H_

// NOTE(xearty): This file is copied from https://github.com/Boostibot/cbasis

// This freestanding file introduces a simple but powerful typed dynamic array concept.
// It works by defining struct for each type and then using type untyped macros to work
// with these structs.
//
// This approach was chosen because:
// 1) we need type safety! Array of int should be distinct type from Array of char
//    This disqualified the one Array struct for all types holding the type info supplied at runtime.
//
// 2) we need to be able to work with empty arrays easily and safely.
//    Empty arrays are the most common arrays so having them as a special and error prone case
//    is less than ideal. This disqualified the typed pointer to allocated array prefixed with header holding
//    the meta data. See how stb library implements "stretchy buffers".
//    This approach also introduces a lot of helper functions instead of simple array.count or whatever.
//
// 3) we need to hold info about allocators used for the array. We should know how to deallocate any array using its allocator.
//
// 4) the array type must be fully explicit. There should never be the case where we return an array from a function and we dont know
//    what kind of array it is/if it even is a dynamic array. This is another issue with the stb style.
//
// This file is also fully freestanding. To compile the function definitions #define MODULE_IMPL_ALL and include it again in .c file.

#include <xtb_core/core.h>
#include <xtb_core/allocator.h>

#include <stdint.h>
#include <stdbool.h>

typedef struct Untyped_Array {
    Allocator* allocator;
    uint8_t* data;
    isize count;
    isize capacity;
} Untyped_Array;

typedef struct Generic_Array {
    Untyped_Array* array;
    uint32_t item_size;
    uint32_t item_align;
} Generic_Array;

#define Array_Aligned(Type, align)               \
    union {                                      \
        Untyped_Array untyped;                   \
        struct {                                 \
            Allocator* allocator;                \
            Type* data;                          \
            isize count;                         \
            isize capacity;                      \
        };                                       \
        uint8_t (*ALIGN)[align];                 \
    }                                            \

#define Array(Type) Array_Aligned(Type, __alignof(Type) > 0 ? __alignof(Type) : 8)

typedef Array(uint8_t)  U8_Array;
typedef Array(uint16_t) U16_Array;
typedef Array(uint32_t) U32_Array;
typedef Array(uint64_t) U64_Array;

typedef Array(int8_t)   I8_Array;
typedef Array(int16_t)  I16_Array;
typedef Array(int32_t)  I32_Array;
typedef Array(int64_t)  I64_Array;

typedef Array(float)    F32_Array;
typedef Array(double)   F64_Array;
typedef Array(void*)    ptr_Array;

typedef I64_Array ISize_Array;
typedef U64_Array USize_Array;

void generic_array_init(Generic_Array gen, Allocator* allocator);
void generic_array_deinit(Generic_Array gen);
void generic_array_set_capacity(Generic_Array gen, isize capacity);
void generic_array_resize(Generic_Array gen, isize to_size, bool zero_new);
void generic_array_reserve(Generic_Array gen, isize to_capacity);
void generic_array_append(Generic_Array gen, const void* data, isize data_count);

#if XTB_LANG_CPP
    #define array_make_generic(array_ptr) (Generic_Array{&(array_ptr)->untyped, sizeof *(array_ptr)->data, sizeof *(array_ptr)->ALIGN})
#else
    #define array_make_generic(array_ptr) ((Generic_Array){&(array_ptr)->untyped, sizeof *(array_ptr)->data, sizeof *(array_ptr)->ALIGN})
#endif

#define make_array(allocator) { (allocator) }

//Initializes the array. If the array is already initialized deinitializes it first.
//Thus expects a properly formed array. Suppling a non-zeroed memory will cause errors!
//All data structers in this library need to be zero init to be valid!
#define array_init(array_ptr, allocator) \
    generic_array_init(array_make_generic(array_ptr), (allocator))

//Deallocates and resets the array
#define array_deinit(array_ptr) \
    generic_array_deinit(array_make_generic(array_ptr))

//If the array capacity is lower than to_capacity sets the capacity to to_capacity.
//If setting of capacity is required and the new capcity is less then one geometric growth
// step away from current capacity grows instead.
#define array_reserve(array_ptr, to_capacity) \
    generic_array_reserve(array_make_generic(array_ptr), (to_capacity))

//Sets the array size to the specied to_size.
//If the to_size is smaller than current size simply dicards further items
//If the to_size is greater than current size zero initializes the newly added items
#define array_resize(array_ptr, to_size) \
    generic_array_resize(array_make_generic(array_ptr), (to_size), true)

//Just like array_resize except doesnt zero initialized newly added region
#define array_resize_for_overwrite(array_ptr, to_size) \
    generic_array_resize(array_make_generic(array_ptr), (to_size), false)

//Sets the array size to 0. Does not deallocate the array
#define array_clear(array_ptr) ((array_ptr)->count = 0)

//Appends item_count items to the end of the array growing it
#define array_append(array_ptr, items, item_count) (                                                 \
        /* Here is a little hack to typecheck the items array.*/                                     \
        /* We do a comparison that emmits a warning on incompatible types but doesnt get executed */ \
        (void) sizeof((array_ptr)->data == (items)),                                                 \
        generic_array_append(array_make_generic(array_ptr), (items), (item_count))                   \
    )                                                                                                \

//Discards current items in the array and replaces them with the provided items
#define array_assign(array_ptr, items, item_count) (     \
        array_clear(array_ptr),                          \
        array_append((array_ptr), (items), (item_count)) \
    )                                                    \

//Appends a single item to the end of the array
#define array_push(array_ptr, item_value) (                                           \
        generic_array_reserve(array_make_generic(array_ptr), (array_ptr)->count + 1), \
        (array_ptr)->data[(array_ptr)->count++] = (item_value)                        \
    )                                                                                 \

//Removes a single item from the end of the array
#define array_pop(array_ptr) (                                                  \
        XTB_CheckBounds(0, (array_ptr)->count, "cannot pop from empty array!"), \
        (array_ptr)->data[--(array_ptr)->count]                                 \
    )                                                                           \

//Removes the item at index and puts the last item in its place to fill the hole
#define array_remove_unordered(array_ptr, index) (                                 \
        XTB_CheckBounds(0, (array_ptr)->count, "cannot remove from empty array!"), \
        (array_ptr)->data[(index)] = (array_ptr)->data[--(array_ptr)->count]       \
    )                                                                              \

//Returns the value of the last item. The array must not be empty!
#define array_last(array) (                                                     \
        XTB_CheckBounds(0, (array).count, "cannot get last from empty array!"), \
        &(array).data[(array).count - 1]                                        \
    )                                                                           \

#define array_set_capacity(array_ptr, capacity) \
    generic_array_set_capacity(array_make_generic(array_ptr), (capacity))
#endif

// #endif // _XTB_ARRAY_H_
