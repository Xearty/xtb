#include "xtb_core/thread_context.h"
#include <xtb_core/allocator.h>
#include <xtb_core/arena.h>
#include <xtb_core/str.h>
#include <xtb_core/linked_list.h>

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    ThreadContext tctx;
    tctx_init_and_equip(&tctx);

    Arena *permanent_arena = arena_new(Kilobytes(4));
    allocator_set_static(&permanent_arena->allocator);

    String str = str("  fani mazakura f ");

    StringList list = str_split_by_whitespace(allocator_get_static(), str);
    IterateList(list, StringListNode, node)
    {
        str_debug(node->string);
    }

    tctx_release();

    return 0;
}
