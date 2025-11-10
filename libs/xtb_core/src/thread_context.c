#include <xtb_core/thread_context.h>
#include <xtb_core/intrinsics.h>

C_LINKAGE XTB_THREAD_STATIC ThreadContext *g_tctx;

void tctx_init_and_equip(ThreadContext *tctx)
{
    MemoryZeroStruct(tctx);
    Arena **arena_ptr = tctx->arenas;
    for (size_t i = 0; i < ArrLen(tctx->arenas); i += 1, arena_ptr += 1)
    {
        *arena_ptr = arena_new(Kilobytes(64));
    }
    g_tctx = tctx;
}

void tctx_release(void)
{
    for (size_t i = 0; i < ArrLen(g_tctx->arenas); i += 1)
    {
        arena_release(g_tctx->arenas[i]);
    }
}

ThreadContext *tctx_get_equipped(void)
{
    return g_tctx;
}

Arena *tctx_get_scratch(Arena **conflicts, size_t count)
{
    ThreadContext *tctx = tctx_get_equipped();

    Arena *result = 0;
    Arena **arena_ptr = tctx->arenas;
    for (size_t i = 0; i < ArrLen(tctx->arenas); i += 1, arena_ptr += 1)
    {
        Arena **conflict_ptr = conflicts;
        bool has_conflict = false;
        for (size_t j = 0; j < count; j += 1, conflict_ptr += 1)
        {
            if (*arena_ptr == *conflict_ptr)
            {
                has_conflict = 1;
                break;
            }
        }
        if (!has_conflict)
        {
            result = *arena_ptr;
            break;
        }
    }

    return result;
}
