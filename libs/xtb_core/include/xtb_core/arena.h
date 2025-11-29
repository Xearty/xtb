#ifndef _XTB_ALLOCATOR_ARENA_H_
#define _XTB_ALLOCATOR_ARENA_H_

#include <xtb_core/core.h>
#include <xtb_core/allocator.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

namespace xtb
{

/****************************
 * Utility macros
 ***************************/
#define push_array(arena, type, count) (type *)arena_alloc((arena), sizeof(type) * (count))
#define push_struct(arena, type) push_array((arena), type, 1)

#define push_array_zero(arena, type, count) (type *)arena_alloc_zero((arena), sizeof(type) * (count))
#define push_struct_zero(arena, type) push_array_zero((arena), type, 1)

#define ARENA_BOOTSTRAP_OVERHEAD (sizeof(Arena) + sizeof(ArenaChunkHeader))

/****************************
 * Arena API
 ***************************/
struct ArenaChunkHeader
{
    size_t capacity;
    size_t offset;
    ArenaChunkHeader *next;
};

struct Arena
{
    Allocator allocator;
    ArenaChunkHeader *base_chunk;
    ArenaChunkHeader *current_chunk;
    size_t base_size;
};

Arena *arena_new(size_t buffer_size);
Arena *arena_new_exact_size(size_t arena_size);
void arena_release(Arena *arena);
bool arena_chunk_has_enough_capacity(ArenaChunkHeader *chunk, size_t allocation_size);

// TODO: deal with alignment
void *arena_alloc(Arena *arena, size_t allocation_size);
void *arena_alloc_zero(Arena *arena, size_t allocation_size);
void arena_clear(Arena *arena);

/****************************
 * Temporary Arena API
 ***************************/
struct TempArenaSnapshot
{
    ArenaChunkHeader *chunk;
    size_t offset;
};

struct TempArena
{
    Arena *arena;
    TempArenaSnapshot snapshot;
};

TempArena temp_arena_new(Arena *arena);
void temp_arena_release(TempArena temp);

/****************************
 * Memory Usage Utilities
 ***************************/
size_t arena_dump_memory_usage(Arena *arena);
size_t arena_dump_memory_usage_pp(Arena *arena, char *buffer, size_t buffer_size);

}

#endif // _XTB_ALLOCATOR_ARENA_H_
