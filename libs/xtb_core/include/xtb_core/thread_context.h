#ifndef _XTB_CORE_THREAD_CONTEXT_H_
#define _XTB_CORE_THREAD_CONTEXT_H_

#include <xtb_core/core.h>
#include <xtb_core/arena.h>

C_LINKAGE_BEGIN

typedef struct ThreadContext
{
    Arena *arenas[2];
} ThreadContext;

void tctx_init_and_equip(ThreadContext *tctx);
void tctx_release(void);
ThreadContext *tctx_get_equipped(void);
Arena *tctx_get_scratch(Arena **conflicts, size_t count);

#define scratch_begin(conflicts, count) temp_arena_new(tctx_get_scratch((conflicts), (count)))
#define scratch_begin_conflict(alloc) scratch_begin((Arena**)(&alloc), 1)
#define scratch_begin_no_conflicts() scratch_begin(NULL, 0)

#define scratch_end(scratch) temp_arena_release(scratch)

#define scratch_scope(name, conflicts, conflicts_count)                      \
    for (TempArena name = scratch_begin((conflicts), (conflicts_count)) \
             , name##_counter = {0};                                             \
         name##_counter.snapshot.offset == 0;                                    \
         name##_counter.snapshot.offset += 1,                                    \
         scratch_end(name))

#define scratch_scope_no_conflicts(name) scratch_scope(name, NULL, 0)
#define scratch_scope_conflict(name, allocator) scratch_scope(name, (Arena**)&(allocator).context, 1)

C_LINKAGE_END

#endif // _XTB_CORE_THREAD_CONTEXT_H_
