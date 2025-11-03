#include "xtb_allocator/malloc.h"
#include <xtb_core/core.h>
#include <xtb_core/str.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/arena.h>

#include <stdio.h>

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    XTB_Arena *arena = xtb_arena_new(XTB_Kilobytes(4));
    XTB_Allocator allocator = xtb_arena_allocator(arena);

    XTB_String8 string = xtb_str8_lit("hello");
    puts(string.str);
    printf("length = %zu\n", string.len);

    XTB_String8 dyn_string = xtb_str8_copy_lit(allocator, "hello there");
    printf("dyn_string = %s, length = %zu\n", dyn_string.str, dyn_string.len);

    XTB_String8_List str_list = {0};
    XTB_String8_List_Node node1 = { xtb_str8_lit("hello ") };
    XTB_String8_List_Node node2 = { xtb_str8_lit("world") };

    SLLQueuePush(str_list.head, str_list.tail, &node1);
    SLLQueuePush(str_list.head, str_list.tail, &node2);

    XTB_String8 concatenated = xtb_str8_list_join(allocator, str_list);
    puts(concatenated.str);

    XTB_String8 test2 = xtb_str8_lit("Nqkakuv dulug string");
    XTB_String8 sub_test2 = xtb_str8_substr_copy(allocator, test2, 10, 5);
    printf("str = \"%s\", len = %zu\n", sub_test2.str, sub_test2.len);

    xtb_arena_drop(arena);

    return 0;
}
