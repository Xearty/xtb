#ifndef _XTB_ALLOCATOR_ARENA_H_
#define _XTB_ALLOCATOR_ARENA_H_

#include <xtb_core/core.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

/****************************
 * Utility macros
 ***************************/
#define PushArray(arena, type, count) (type *)xtb_arena_alloc((arena), sizeof(type) * (count))
#define PushStruct(arena, type) PushArray((arena), type, 1)

#define PushArrayZero(arena, type, count) (type *)xtb_arena_alloc_zero((arena), sizeof(type) * (count))
#define PushStructZero(arena, type) PushArrayZero((arena), type, 1)

#define XTB_ARENA_BOOTSTRAP_OVERHEAD (sizeof(XTB_Arena) + sizeof(XTB_Arena_Chunk_Header))

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

typedef struct XTB_Arena XTB_Arena;
struct XTB_Arena
{
    XTB_Arena_Chunk_Header *base_chunk;
    XTB_Arena_Chunk_Header *current_chunk;
    size_t base_size;
};

XTB_Arena *xtb_arena_new(size_t buffer_size);
XTB_Arena *xtb_arena_new_exact_size(size_t arena_size);
void xtb_arena_drop(XTB_Arena *arena);
bool xtb_arena_chunk_has_enough_capacity(XTB_Arena_Chunk_Header *chunk, size_t allocation_size);

// TODO: deal with alignment
void *xtb_arena_alloc(XTB_Arena *arena, size_t allocation_size);
static void *xtb_arena_alloc_zero(XTB_Arena *arena, size_t allocation_size);
void xtb_arena_clear(XTB_Arena *arena);

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
    XTB_Arena *arena;
    XTB_Temp_Arena_Snapshot snapshot;
};

XTB_Temp_Arena xtb_temp_arena_new(XTB_Arena *arena);
void xtb_temp_arena_drop(XTB_Temp_Arena temp);

/****************************
 * Memory Usage Utilities
 ***************************/
size_t xtb_arena_dump_memory_usage(XTB_Arena *arena);
size_t xtb_arena_dump_memory_usage_pp(XTB_Arena *arena, char *buffer, size_t buffer_size);

/****************************
 * Allocator Interface
 ***************************/
XTB_Allocator xtb_arena_allocator(XTB_Arena *arena);

#endif // _XTB_ALLOCATOR_ARENA_H_
