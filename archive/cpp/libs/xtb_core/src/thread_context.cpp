#include <xtb_core/thread_context.h>
#include <xtb_core/intrinsics.h>
#include <xtb_core/contract.h>

namespace xtb
{

thread_local ThreadContext *g_tctx;

void ThreadContext::init(ThreadContext* tctx)
{
    Assert(g_tctx == NULL);

    MemoryZeroStruct(tctx);
    Arena **arena_ptr = tctx->arenas;
    for (size_t i = 0; i < ArrLen(tctx->arenas); i += 1, arena_ptr += 1)
    {
        *arena_ptr = arena_new(Kilobytes(64));
    }
    g_tctx = tctx;
}

void ThreadContext::deinit()
{
    for (size_t i = 0; i < ArrLen(g_tctx->arenas); i += 1)
    {
        arena_release(g_tctx->arenas[i]);
    }
}

ThreadContext* ThreadContext::get()
{
    Assert(g_tctx != NULL);
    return g_tctx;
}

Arena *ThreadContext::get_scratch(Arena **conflicts, isize count)
{
    ThreadContext *tctx = ThreadContext::get();

    Arena *result = 0;
    Arena **arena_ptr = tctx->arenas;
    for (size_t i = 0; i < ArrLen(tctx->arenas); i += 1, arena_ptr += 1)
    {
        Arena **conflict_ptr = conflicts;
        bool has_conflict = false;
        for (isize j = 0; j < count; j += 1, conflict_ptr += 1)
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

}
