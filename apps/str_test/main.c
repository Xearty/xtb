#define XTB_STR_SHORTHAND

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

    String8 string = str8_lit("hello");
    puts(string.str);
    printf("length = %zu\n", string.len);

    String8 dyn_string = str8_lit_copy(allocator, "hello there");
    printf("dyn_string = %s, length = %zu\n", dyn_string.str, dyn_string.len);

    String8_List str_list = {0};
    String8_List_Node node1 = { str8_lit("hello ") };
    String8_List_Node node2 = { str8_lit("world") };

    SLLQueuePush(str_list.head, str_list.tail, &node1);
    SLLQueuePush(str_list.head, str_list.tail, &node2);

    String8 concatenated = str8_list_join(allocator, str_list);
    puts(concatenated.str);

    String8 test2 = str8_lit("Nqkakuv dulug string");
    String8 sub_test2 = str8_substr_copy(allocator, test2, 10, 5);
    printf("str = \"%s\", len = %zu\n", sub_test2.str, sub_test2.len);

    XTB_Temp_Arena temp = xtb_scratch_begin(NULL, 0);
    XTB_Allocator temp_allocator = xtb_arena_allocator(temp.arena);

    String8_List list = {0};
    str8_list_push(temp_allocator, &list, str8_lit("a"));
    str8_list_push(temp_allocator, &list, str8_lit("b"));
    str8_list_push(temp_allocator, &list, str8_lit("c"));
    str8_list_push(temp_allocator, &list, str8_lit("d"));
    str8_list_push(temp_allocator, &list, str8_lit("e"));

    String8 sep = str8_lit(".");
    String8 joined = str8_list_join_str_sep(allocator, list, sep);
    puts(joined.str);

    if (str8_eq_lit(joined, "a.b.c.d.e"))
    {
        puts("The strings are equal");
    }
    else
    {
        puts("The strings are different");
    }

    String8 test3 = str8_lit("Hello world");
    test3 = str8_trunc_left(test3, 3);
    test3 = str8_trunc_right(test3, 4);
    test3 = str8_copy(temp_allocator, test3);
    puts(test3.str);

    String8 test4 = str8_lit("\t \n  First  \n \t  \t\t \r Second\n \t\t \r\n");
    String8 test5 = test4;
    test5 = str8_copy(temp_allocator, str8_trim_left(test4));
    printf("Left trimmed: \"%s\"\n", test5.str);

    test5 = str8_copy(temp_allocator, str8_trim_right(test4));
    printf("Right trimmed: \"%s\"\n", test5.str);

    test5 = str8_copy(temp_allocator, str8_trim(test4));
    printf("Trimmed both ways: \"%s\"\n", test5.str);

    String8 test6 = str8_trim_copy(temp_allocator, test4);
    printf("Trimmed both ways copy: \"%s\"\n", test6.str);

    String8 char_split_str = str8_lit("Very long string that contains multiple tokens");
    String8_List char_split_list = str8_split_by_char(temp_allocator, char_split_str, ' ');
    String8 char_joined = str8_list_join_str_sep(temp_allocator, char_split_list, str8_lit("<sep>"));
    puts(char_joined.str);

    String8 str_split_str = str8_lit("Very long  string that contains  multiple tokens");
    String8_List str_split_list = str8_split_by_str(temp_allocator, str_split_str, str8_lit("  "));
    String8 str_joined = str8_list_join_str_sep(temp_allocator, str_split_list, str8_lit("---"));
    puts(str_joined.str);

    String8 space_split_str = str8_lit("\t\n\r\r\n Very \t long  \rstring\r\rthat contains \r \nmultiple \n\r\r\n\ttokens\t\n\t");
    String8_List space_split_list = str8_split_by_whitespace(temp_allocator, space_split_str);
    String8 space_joined = str8_list_join_char_sep(temp_allocator, space_split_list, '-');
    puts(space_joined.str);

    String8 concatenated2 = str8_list_join(temp_allocator, space_split_list);
    str8_debug(concatenated2);

    xtb_scratch_end(temp);

    String8 formatted = str8_format(allocator, "The answer is %d", 42);
    str8_debug(formatted);

    String8 head_tail = str8_lit("head<>tail");
    String8 head = str8_head(head_tail, 4);
    String8 tail = str8_tail(head_tail, 4);
    str8_debug(head_tail);
    str8_debug(head);
    str8_debug(tail);

    if (!str8_starts_with_lit(head_tail, "head"))
    {
        XTB_ASSERT(false);
    }

    if (!str8_ends_with_lit(head_tail, "tail"))
    {
        XTB_ASSERT(false);
    }

    String8 concat = str8_concat_lit(allocator, str8_lit("hello "), "world");
    str8_debug(concat);

    String8 str = str8_lit("hello");
    str = str8_concat(allocator, str, str8_lit(" world"));
    str8_debug(str);

    xtb_arena_drop(arena);
    xtb_tctx_release();

    return 0;
}
