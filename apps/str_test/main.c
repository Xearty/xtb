#include "xtb_allocator/malloc.h"
#include <xtb_core/core.h>
#include <xtb_core/str.h>
#include <xtb_core/linked_list.h>

#include <stdio.h>

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    XTB_String8 string = xtb_str8_lit("hello");
    puts(string.str);
    printf("length = %zu\n", string.len);

    XTB_Allocator allocator = xtb_malloc_allocator();
    XTB_String8 dyn_string = xtb_str8_copy_lit(allocator, "hello there");
    printf("dyn_string = %s, length = %zu\n", dyn_string.str, dyn_string.len);
    xtb_str8_free(allocator, dyn_string);

    XTB_String8_List str_list = {0};
    XTB_String8_List_Node node1 = { xtb_str8_lit("hello ") };
    XTB_String8_List_Node node2 = { xtb_str8_lit("world") };

    SLLQueuePush(str_list.head, str_list.tail, &node1);
    SLLQueuePush(str_list.head, str_list.tail, &node2);

    XTB_String8 concatenated = xtb_str8_list_join(xtb_malloc_allocator(), str_list);
    puts(concatenated.str);

    xtb_str8_free(xtb_malloc_allocator(), concatenated);

    return 0;
}
