#ifndef _XTB_CORE_THREAD_CONTEXT_H_
#define _XTB_CORE_THREAD_CONTEXT_H_

#include "arena.h"

typedef struct XTB_Thread_Context
{
    XTB_Arena *arenas[2];
} XTB_Thread_Context;

void xtb_tctx_init_and_equip(XTB_Thread_Context *tctx);
void xtb_tctx_release(void);
XTB_Thread_Context *xtb_tctx_get_equipped(void);
XTB_Arena *xtb_tctx_get_scratch(XTB_Arena **conflicts, size_t count);

#define xtb_scratch_begin(conflicts, count) xtb_temp_arena_new(xtb_tctx_get_scratch((conflicts), (count)))
#define xtb_scratch_end(scratch) xtb_temp_arena_drop(scratch)

#ifdef XTB_THREAD_CONTEXT_SHORTHAND
typedef XTB_Thread_Context Thread_Context;

#define tctx_init_and_equip xtb_tctx_init_and_equip
#define tctx_release xtb_tctx_release
#define tctx_get_equipped xtb_tctx_get_equipped
#define tctx_get_scratch xtb_tctx_get_scratch

#define scratch_begin xtb_scratch_begin
#define scratch_end xtb_scratch_end
#endif

#endif // _XTB_CORE_THREAD_CONTEXT_H_
