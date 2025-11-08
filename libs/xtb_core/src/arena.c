#include <xtb_core/arena.h>
#include <xtb_core/contract.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

/****************************
 * Internals
 ***************************/
void* arena_allocator_procedure(void* alloc, int64_t new_size, void* old_ptr, int64_t old_size, int64_t align)
{
    XTB_ASSERT(new_size >= 0 && old_size >= 0 && align >= 0);

    XTB_Arena *arena = (XTB_Arena*)alloc;

    void* new_ptr = NULL;

    if (new_size != 0)
    {
        new_ptr = xtb_arena_alloc(arena, new_size);
    }

    return new_ptr;
}

static void arena_free_chunks_after(XTB_Arena_Chunk_Header *chunk)
{
    XTB_Arena_Chunk_Header *chunk_iter = chunk->next;

    while (chunk_iter != NULL)
    {
        XTB_Arena_Chunk_Header *current = chunk_iter;
        chunk_iter = chunk_iter->next;

        free(current);
    }
}

static void *chunk_buffer(XTB_Arena_Chunk_Header *header)
{
    return (char *)header + sizeof(XTB_Arena_Chunk_Header);
}

static size_t determine_chunk_size(XTB_Arena *arena, size_t allocation_size)
{
    return allocation_size > arena->base_size
               ? allocation_size
               : arena->base_size;
}

static XTB_Arena_Chunk_Header *arena_alloc_chunk(size_t chunk_size)
{
    const size_t new_chunk_size = sizeof(XTB_Arena_Chunk_Header) + chunk_size;
    char *arena_chunk_buffer = (char *)malloc(new_chunk_size);

    // fprintf(stderr, "Allocating a new buffer with size: %zu\n", chunk_size);

    XTB_Arena_Chunk_Header *chunk = (XTB_Arena_Chunk_Header *)arena_chunk_buffer;
    chunk->capacity = chunk_size;
    chunk->offset = 0;
    chunk->next = NULL;

    return chunk;
}

static void arena_grow(XTB_Arena *arena, size_t allocation_size)
{
    size_t new_chunk_size = determine_chunk_size(arena, allocation_size);
    XTB_Arena_Chunk_Header *new_chunk = arena_alloc_chunk(new_chunk_size);

    arena->current_chunk->next = new_chunk;
    arena->current_chunk = new_chunk;
}

static void *arena_alloc_in_chunk(XTB_Arena_Chunk_Header *chunk, size_t allocation_size)
{
    void *allocation = (char *)chunk_buffer(chunk) + chunk->offset;
    chunk->offset += allocation_size;
    return allocation;
}

static bool arena_next_chunk_can_hold_allocation(XTB_Arena *arena, size_t allocation_size)
{
    XTB_Arena_Chunk_Header *next_chunk = arena->current_chunk->next;
    return next_chunk != NULL && next_chunk->capacity >= allocation_size;
}

/****************************
 * Arena API
 ***************************/
XTB_Arena *xtb_arena_new(size_t buffer_size)
{
    const size_t arena_offset = 0;
    const size_t chunk_header_offset = arena_offset + sizeof(XTB_Arena);
    const size_t memory_offset = chunk_header_offset + sizeof(XTB_Arena_Chunk_Header);

    const size_t bootstrap_buffer_size = memory_offset + buffer_size;
    char *bootstrap_buffer = (char *)malloc(bootstrap_buffer_size);
    // printf("bootstrap_buffer_size: %zu\n", bootstrap_buffer_size);

    XTB_Arena_Chunk_Header *chunk_header = (XTB_Arena_Chunk_Header *)(bootstrap_buffer + chunk_header_offset);
    chunk_header->capacity = buffer_size;
    chunk_header->offset = 0;
    chunk_header->next = NULL;

    XTB_Arena *arena = (XTB_Arena *)(bootstrap_buffer);
    arena->base_chunk = chunk_header;
    arena->current_chunk = chunk_header;
    arena->base_size = buffer_size;
    arena->allocator = arena_allocator_procedure;

    return arena;
}

XTB_Arena *xtb_arena_new_exact_size(size_t arena_size)
{
    return xtb_arena_new(arena_size - XTB_ARENA_BOOTSTRAP_OVERHEAD);
}

void xtb_arena_release(XTB_Arena *arena)
{
    arena_free_chunks_after(arena->current_chunk);
    free(arena);
}

bool xtb_arena_chunk_has_enough_capacity(XTB_Arena_Chunk_Header *chunk, size_t allocation_size)
{
    return chunk->offset + allocation_size <= chunk->capacity;
}
//
// TODO: deal with alignment
void *xtb_arena_alloc(XTB_Arena *arena, size_t allocation_size)
{
    if (!xtb_arena_chunk_has_enough_capacity(arena->current_chunk, allocation_size))
    {
        if (arena_next_chunk_can_hold_allocation(arena, allocation_size))
        {
            // Reuse already available chunk
            arena->current_chunk = arena->current_chunk->next;
        }
        else
        {
            arena_free_chunks_after(arena->current_chunk);
            arena_grow(arena, allocation_size);
        }
    }

    return arena_alloc_in_chunk(arena->current_chunk, allocation_size);
}

void *xtb_arena_alloc_zero(XTB_Arena *arena, size_t allocation_size)
{
    void *result = xtb_arena_alloc(arena, allocation_size);
    memset(result, 0, allocation_size);
    return result;
}

void xtb_arena_clear(XTB_Arena *arena)
{
    for (XTB_Arena_Chunk_Header *chunk = arena->base_chunk;
         chunk != NULL;
         chunk = chunk->next)
    {
        chunk->offset = 0;
    }

    arena->current_chunk = arena->base_chunk;
}

/****************************
 * Temporary Arena API
 ***************************/
XTB_Temp_Arena xtb_temp_arena_new(XTB_Arena *arena)
{
    XTB_Temp_Arena temp = {};
    temp.arena = arena;
    temp.snapshot.chunk = arena->current_chunk;
    temp.snapshot.offset = arena->current_chunk->offset;

    return temp;
}

void xtb_temp_arena_release(XTB_Temp_Arena temp)
{
    XTB_Arena *arena = temp.arena;
    arena->current_chunk = temp.snapshot.chunk;
    arena->current_chunk->offset = temp.snapshot.offset;
}

/****************************
 * Memory Usage Utilities
 ***************************/
size_t xtb_arena_dump_memory_usage(XTB_Arena *arena)
{
    size_t total_usage = sizeof(XTB_Arena);

    for (XTB_Arena_Chunk_Header *chunk = arena->base_chunk;
         chunk != NULL;
         chunk = chunk->next)
    {
        total_usage += sizeof(XTB_Arena_Chunk_Header);
        total_usage += chunk->offset;
    }

    return total_usage;
}

/// pretty print memory usage
size_t xtb_arena_dump_memory_usage_pp(XTB_Arena *arena, char *buffer, size_t buffer_size)
{
    size_t usage = xtb_arena_dump_memory_usage(arena);

    const char *suffix = "B";
    size_t divisor = 1;

    if (usage / (1024 * 1024 * 1024))
    {
        suffix = "GB";
        divisor = 1024 * 1024 * 1024;
    }
    else if (usage / (1024 * 1024))
    {
        suffix = "MB";
        divisor = 1024 * 1024;
    }
    else if (usage / 1024 != 0)
    {
        suffix = "KB";
        divisor = 1024;
    }

    double unit_count = (double)usage / (double)divisor;
    snprintf(buffer, buffer_size, "%.1lf%s", unit_count, suffix);

    return usage;
}

