#undef XTB_SHORTHANDS

#include <xtb_core/core.hpp>
#include <xtb_core/arena.h>
#include <xtb_core/allocator.h>
#include <xtb_core/thread_context.h>

namespace xtb
{
}

using namespace xtb;

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    XTB_Thread_Context tctx;
    xtb_tctx_init_and_equip(&tctx);

    // ...

    xtb_tctx_release();

    return 0;
}
