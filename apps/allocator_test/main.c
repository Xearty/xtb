#include "xtb_core/thread_context.h"
#include <xtb_core/allocator.h>
#include <xtb_core/arena.h>
#include <xtb_core/str.h>
#include <xtb_core/linked_list.h>

#include <stdio.h>

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    Thread_Context tctx;
    tctx_init_and_equip(&tctx);

    puts("Working");

    XTB_Arena *arena = xtb_arena_new(1000);

    XTB_String8 str = xtb_str8_lit("  fani mazakura f ");

    Allocator *allocator = allocator_get_malloc();

    XTB_String8_List list = str8_split_by_whitespace(allocator, str);
    XTB_IterateList(list, XTB_String8_List_Node, node)
    {
        str8_debug(node->string);
    }

    xtb_arena_release(arena);

    tctx_release();

    return 0;
}
