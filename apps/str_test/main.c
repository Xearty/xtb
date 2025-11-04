#include <xtb_core/core.h>
#include <xtb_core/str.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/arena.h>
#include <xtb_core/thread_context.h>

#include <stdio.h>

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    XTB_Thread_Context tctx;
    xtb_tctx_init_and_equip(&tctx);

    XTB_Arena *arena = xtb_arena_new(XTB_Kilobytes(4));
    XTB_Allocator allocator = xtb_arena_allocator(arena);

    XTB_String8 string = xtb_str8_lit("hello");
    puts(string.str);
    printf("length = %zu\n", string.len);

    XTB_String8 dyn_string = xtb_str8_lit_copy(allocator, "hello there");
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

    XTB_Temp_Arena temp = xtb_scratch_begin(NULL, 0);
    XTB_Allocator temp_allocator = xtb_arena_allocator(temp.arena);

    XTB_String8_List list = {0};
    xtb_str8_list_push(temp_allocator, &list, xtb_str8_lit("a"));
    xtb_str8_list_push(temp_allocator, &list, xtb_str8_lit("b"));
    xtb_str8_list_push(temp_allocator, &list, xtb_str8_lit("c"));
    xtb_str8_list_push(temp_allocator, &list, xtb_str8_lit("d"));
    xtb_str8_list_push(temp_allocator, &list, xtb_str8_lit("e"));

    XTB_String8 sep = xtb_str8_lit(".");
    XTB_String8 joined = xtb_str8_list_join_str_sep(allocator, list, sep);
    puts(joined.str);

    if (xtb_str8_eq_lit(joined, "a.b.c.d.e"))
    {
        puts("The strings are equal");
    }
    else
    {
        puts("The strings are different");
    }

    XTB_String8 test3 = xtb_str8_lit("Hello world");
    test3 = xtb_str8_trunc_left(test3, 3);
    test3 = xtb_str8_trunc_right(test3, 4);
    test3 = xtb_str8_copy(temp_allocator, test3);
    puts(test3.str);

    XTB_String8 test4 = xtb_str8_lit("\t \n  First  \n \t  \t\t \r Second\n \t\t \r\n");
    XTB_String8 test5 = test4;
    test5 = xtb_str8_copy(temp_allocator, xtb_str8_trim_left(test4));
    printf("Left trimmed: \"%s\"\n", test5.str);

    test5 = xtb_str8_copy(temp_allocator, xtb_str8_trim_right(test4));
    printf("Right trimmed: \"%s\"\n", test5.str);

    test5 = xtb_str8_copy(temp_allocator, xtb_str8_trim(test4));
    printf("Trimmed both ways: \"%s\"\n", test5.str);

    XTB_String8 test6 = xtb_str8_trim_copy(temp_allocator, test4);
    printf("Trimmed both ways copy: \"%s\"\n", test6.str);

    XTB_String8 char_split_str = xtb_str8_lit("Very long string that contains multiple tokens");
    XTB_String8_List char_split_list = xtb_str8_list_split_by_char(temp_allocator, char_split_str, ' ');
    XTB_String8 char_joined = xtb_str8_list_join_str_sep(temp_allocator, char_split_list, xtb_str8_lit("<sep>"));
    puts(char_joined.str);

    XTB_String8 str_split_str = xtb_str8_lit("Very long  string that contains  multiple tokens");
    XTB_String8_List str_split_list = xtb_str8_list_split_by_str(temp_allocator, str_split_str, xtb_str8_lit("  "));
    XTB_String8 str_joined = xtb_str8_list_join_str_sep(temp_allocator, str_split_list, xtb_str8_lit("---"));
    puts(str_joined.str);

    XTB_String8 space_split_str = xtb_str8_lit("\t\n\r Very \t long  \rstring\r\rthat contains \r \nmultiple \n\r\r\n\ttokens\t\n\t");
    XTB_String8_List space_split_list = xtb_str8_list_split_by_whitespace(temp_allocator, space_split_str);
    XTB_String8 space_joined = xtb_str8_list_join_char_sep(temp_allocator, space_split_list, '-');
    puts(space_joined.str);

    XTB_String8 concatenated2 = xtb_str8_list_join(temp_allocator, space_split_list);
    xtb_str8_debug(concatenated2);

    xtb_scratch_end(temp);

    XTB_String8 formatted = xtb_str8_format(allocator, "The answer is %d", 42);
    xtb_str8_debug(formatted);

    xtb_arena_drop(arena);
    xtb_tctx_release();

    return 0;
}
