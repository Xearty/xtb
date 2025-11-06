#undef XTB_SHORTHANDS

#include <iostream>

#include <xtb_core/core.hpp>
#include <xtb_core/arena.h>
#include <xtb_core/allocator.h>
#include <xtb_core/thread_context.h>

namespace xtb
{

namespace arena
{
    struct Arena {
        XTB_Arena *raw;

        explicit Arena(XTB_Arena *raw) : raw(raw) {}

        operator XTB_Allocator()
        {
            return xtb_arena_allocator(this->raw);
        }

        void release()
        {
            xtb_arena_release(this->raw);
        }

        template <typename T>
        T* alloc()
        {
            return xtb_arena_alloc(this->raw, sizeof(T));
        }

        template <typename T>
        T* alloc_array(size_t count)
        {
            return xtb_arena_alloc(this->raw, count * sizeof(T));
        }

        static Arena create(int size)
        {
            return Arena(xtb_arena_new(size));
        }
    };
}

}

int *allocates(XTB_Allocator allocator, int value)
{
    int *allocation = XTB_Allocate(allocator, int);
    *allocation = value;
    return allocation;
}

using namespace xtb;
using Arena = xtb::arena::Arena;

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    XTB_Thread_Context tctx;
    xtb_tctx_init_and_equip(&tctx);

    Arena arena = Arena::create(XTB_Kilobytes(4));
    defer(arena.release());

    // XTB_Arena *arena = xtb_arena_new(XTB_Kilobytes(4));

    std::cout << "Hello, World" << std::endl;

    int *allocation = allocates(arena, 42);
    std::cout << "Value: " << *allocation << std::endl;

    xtb_tctx_release();

    return 0;
}
