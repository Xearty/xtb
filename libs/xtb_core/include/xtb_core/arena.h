#ifndef _XTB_ALLOCATOR_ARENA_H_
#define _XTB_ALLOCATOR_ARENA_H_

#include <xtb_core/core.h>
#include <xtb_core/allocator.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

XTB_C_LINKAGE_BEGIN

/****************************
 * Utility macros
 ***************************/
#define xtb_push_array(arena, type, count) (type *)xtb_arena_alloc((arena), sizeof(type) * (count))
#define xtb_push_struct(arena, type) xtb_push_array((arena), type, 1)

#define xtb_push_array_zero(arena, type, count) (type *)xtb_arena_alloc_zero((arena), sizeof(type) * (count))
#define xtb_push_struct_zero(arena, type) xtb_push_array_zero((arena), type, 1)

#define XTB_ARENA_BOOTSTRAP_OVERHEAD (sizeof(Arena) + sizeof(XTB_Arena_Chunk_Header))

/****************************
 * Arena API
 ***************************/
typedef struct XTB_Arena_Chunk_Header XTB_Arena_Chunk_Header;
struct XTB_Arena_Chunk_Header
{
    size_t capacity;
    size_t offset;
    XTB_Arena_Chunk_Header *next;
};

typedef struct Arena Arena;
struct Arena
{
    Allocator allocator;
    XTB_Arena_Chunk_Header *base_chunk;
    XTB_Arena_Chunk_Header *current_chunk;
    size_t base_size;
};

Arena *xtb_arena_new(size_t buffer_size);
Arena *xtb_arena_new_exact_size(size_t arena_size);
void xtb_arena_release(Arena *arena);
bool xtb_arena_chunk_has_enough_capacity(XTB_Arena_Chunk_Header *chunk, size_t allocation_size);

// TODO: deal with alignment
void *xtb_arena_alloc(Arena *arena, size_t allocation_size);
void *xtb_arena_alloc_zero(Arena *arena, size_t allocation_size);
void xtb_arena_clear(Arena *arena);

/****************************
 * Temporary Arena API
 ***************************/
typedef struct XTB_Temp_Arena_Snapshot XTB_Temp_Arena_Snapshot;
struct XTB_Temp_Arena_Snapshot
{
    XTB_Arena_Chunk_Header *chunk;
    size_t offset;
};

typedef struct XTB_Temp_Arena XTB_Temp_Arena;
struct XTB_Temp_Arena
{
    Arena *arena;
    XTB_Temp_Arena_Snapshot snapshot;
};

XTB_Temp_Arena xtb_temp_arena_new(Arena *arena);
void xtb_temp_arena_release(XTB_Temp_Arena temp);

/****************************
 * Memory Usage Utilities
 ***************************/
size_t xtb_arena_dump_memory_usage(Arena *arena);
size_t xtb_arena_dump_memory_usage_pp(Arena *arena, char *buffer, size_t buffer_size);

/****************************
 * Allocator Interface
 ***************************/
#ifdef XTB_ARENA_SHORTHANDS
typedef Arena Arena;

#define arena_new xtb_arena_new
#define arena_new_exact_size xtb_arena_new_exact_size
#define arena_release xtb_arena_release
#define arena_alloc xtb_arena_alloc
#define arena_alloc_zero xtb_arena_alloc_zero
#define arena_clear xtb_arena_clear

typedef XTB_Temp_Arena Temp_Arena;
#define temp_arena_new xtb_temp_arena_new
#define temp_arena_release xtb_temp_arena_release

#define push_array xtb_push_array
#define push_struct xtb_push_struct
#define push_array_zero xtb_push_array_zero
#define push_struct_zero xtb_push_struct_zero

#define arena_allocator xtb_arena_allocator
#endif

XTB_C_LINKAGE_END

#endif // _XTB_ALLOCATOR_ARENA_H_
