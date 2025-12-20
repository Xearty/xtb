#ifndef _XTB_CORE_THREAD_CONTEXT_H_
#define _XTB_CORE_THREAD_CONTEXT_H_

#include <xtb_core/core.h>
#include <xtb_core/arena.h>

namespace xtb
{

struct ThreadContext
{
    Arena *arenas[2];

    static void init(ThreadContext* tctx);
    static void deinit();
    static ThreadContext* get();
    static Arena* get_scratch(Arena** conflicts, isize count);
};

struct ThreadContextScope
{
    ThreadContext tctx;

    ThreadContextScope()
    {
        ThreadContext::init(&this->tctx);
    }

    ~ThreadContextScope()
    {
        ThreadContext::deinit();
    }
};

struct ScratchScope
{
    TempArena scratch;

    ScratchScope()
    {
        Arena* scratch_arena = ThreadContext::get_scratch(NULL, 0);
        this->scratch = temp_arena_new(scratch_arena);
    }

    ScratchScope(Allocator* conflict)
    {
        Arena* scratch_arena = ThreadContext::get_scratch((Arena**)&conflict, 1);
        this->scratch = temp_arena_new(scratch_arena);
    }

    ~ScratchScope()
    {
        temp_arena_release(this->scratch);
    }

    Arena* operator*()
    {
        return this->scratch.arena;
    }

    Arena* operator->()
    {
        return this->scratch.arena;
    }
};

}

#endif // _XTB_CORE_THREAD_CONTEXT_H_
