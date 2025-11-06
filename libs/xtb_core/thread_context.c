#include "thread_context.h"
#include "core.h"

XTB_C_LINKAGE XTB_THREAD_STATIC XTB_Thread_Context *g_tctx;

void xtb_tctx_init_and_equip(XTB_Thread_Context *tctx)
{
    XTB_MemoryZeroStruct(tctx);
    XTB_Arena **arena_ptr = tctx->arenas;
    for (size_t i = 0; i < XTB_ArrLen(tctx->arenas); i += 1, arena_ptr += 1)
    {
        *arena_ptr = xtb_arena_new(XTB_Kilobytes(64));
    }
    g_tctx = tctx;
}

void xtb_tctx_release(void)
{
    for (size_t i = 0; i < XTB_ArrLen(g_tctx->arenas); i += 1)
    {
        xtb_arena_release(g_tctx->arenas[i]);
    }
}

XTB_Thread_Context *xtb_tctx_get_equipped(void)
{
    return g_tctx;
}

XTB_Arena *xtb_tctx_get_scratch(XTB_Arena **conflicts, size_t count)
{
    XTB_Thread_Context *tctx = xtb_tctx_get_equipped();

    XTB_Arena *result = 0;
    XTB_Arena **arena_ptr = tctx->arenas;
    for (size_t i = 0; i < XTB_ArrLen(tctx->arenas); i += 1, arena_ptr += 1)
    {
        XTB_Arena **conflict_ptr = conflicts;
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
