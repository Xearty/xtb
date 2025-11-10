#include <xtb_core/core.h>
#include <xtb_core/str.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/arena.h>
#include <xtb_core/thread_context.h>
#include <xtb_core/str_buffer.h>
#include <xtb_core/contract.h>

#include <stdio.h>

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    ThreadContext tctx;
    tctx_init_and_equip(&tctx);

    Arena *arena = arena_new(Kilobytes(4));

    String string = str("hello");
    puts(string.str);
    printf("length = %zu\n", string.len);

    String dyn_string = str_copy(&arena->allocator, str("hello there"));
    printf("dyn_string = %s, length = %zu\n", dyn_string.str, dyn_string.len);

    StringList str_list = {0};
    StringListNode node1 = { str("hello ") };
    StringListNode node2 = { str("world") };

    SLLQueuePush(str_list.head, str_list.tail, &node1);
    SLLQueuePush(str_list.head, str_list.tail, &node2);

    String concatenated = str_list_join(&arena->allocator, str_list);
    puts(concatenated.str);

    String test2 = str("Nqkakuv dulug string");
    String sub_test2 = str_substr_copy(&arena->allocator, test2, 10, 5);
    printf("str = \"%s\", len = %zu\n", sub_test2.str, sub_test2.len);

    TempArena temp = scratch_begin(NULL, 0);

    StringList list = {0};
    str_list_push(&temp.arena->allocator, &list, str("a"));
    str_list_push(&temp.arena->allocator, &list, str("b"));
    str_list_push(&temp.arena->allocator, &list, str("c"));
    str_list_push(&temp.arena->allocator, &list, str("d"));
    str_list_push(&temp.arena->allocator, &list, str("e"));

    String sep = str(".");
    String joined = str_list_join_str_sep(&arena->allocator, list, sep);
    puts(joined.str);

    if (str_eq_lit(joined, "a.b.c.d.e"))
    {
        puts("The strings are equal");
    }
    else
    {
        puts("The strings are different");
    }

    String test3 = str("Hello world");
    test3 = str_trunc_left(test3, 3);
    test3 = str_trunc_right(test3, 4);
    test3 = str_copy(&temp.arena->allocator, test3);
    puts(test3.str);

    String test4 = str("\t \n  First  \n \t  \t\t \r Second\n \t\t \r\n");
    String test5 = test4;
    test5 = str_copy(&temp.arena->allocator, str_trim_left(test4));
    printf("Left trimmed: \"%s\"\n", test5.str);

    test5 = str_copy(&temp.arena->allocator, str_trim_right(test4));
    printf("Right trimmed: \"%s\"\n", test5.str);

    test5 = str_copy(&temp.arena->allocator, str_trim(test4));
    printf("Trimmed both ways: \"%s\"\n", test5.str);

    String test6 = str_trim_copy(&temp.arena->allocator, test4);
    printf("Trimmed both ways copy: \"%s\"\n", test6.str);

    String char_split_str = str("Very long string that contains multiple tokens");
    StringList char_split_list = str_split_by_char(&temp.arena->allocator, char_split_str, ' ');
    String char_joined = str_list_join_str_sep(&temp.arena->allocator, char_split_list, str("<sep>"));
    puts(char_joined.str);

    String str_split_str = str("Very long  string that contains  multiple tokens");
    StringList str_split_list = str_split_by_str(&temp.arena->allocator, str_split_str, str("  "));
    String str_joined = str_list_join_str_sep(&temp.arena->allocator, str_split_list, str("---"));
    puts(str_joined.str);

    String space_split_str = str("\t\n\r\r\n Very \t long  \rstring\r\rthat contains \r \nmultiple \n\r\r\n\ttokens\t\n\t");
    StringList space_split_list = str_split_by_whitespace(&temp.arena->allocator, space_split_str);
    String space_joined = str_list_join_char_sep(&temp.arena->allocator, space_split_list, '-');
    puts(space_joined.str);

    String concatenated2 = str_list_join(&temp.arena->allocator, space_split_list);
    str_debug(concatenated2);

    scratch_end(temp);

    String formatted = str_format(&arena->allocator, "The answer is %d", 42);
    str_debug(formatted);

    String head_tail = str("head<>tail");
    String head = str_head(head_tail, 4);
    String tail = str_tail(head_tail, 4);
    str_debug(head_tail);
    str_debug(head);
    str_debug(tail);

    if (!str_starts_with_lit(head_tail, "head"))
    {
        Assert(false);
    }

    if (!str_ends_with_lit(head_tail, "tail"))
    {
        Assert(false);
    }

    String concat = str_concat_lit(&arena->allocator, str("hello "), "world");
    str_debug(concat);

    String str = str("hello");
    str = str_concat(&arena->allocator, str, str(" world"));
    str_debug(str);

    puts("----------------------String Buffer------------------------");
    {
        TempArena scratch = scratch_begin(0, 0);

        // This will be allocated on the scratch arena
        StringBuffer str_buffer = str_buffer_new(&scratch.arena->allocator, 0);
        for (int i = 0; i < 10; ++i)
        {
            String hello = str("hello");
            str_buffer_push_back(&str_buffer, hello);
            str_buffer_push_back_cstring(&str_buffer, " ");
            str_buffer_push_front_lit(&str_buffer, "not ");
            str_buffer_push_back_lit(&str_buffer, "world");
            str_buffer_push_back_cstring(&str_buffer, "!");
        }

        // This is allocated on the persistent arena
        String owned_str = str_buffer_view_copy(&arena->allocator, &str_buffer);

        scratch_end(scratch);

        str_debug(owned_str);
    }
    puts("-----------------------------------------------------------");

    String escaped = str_escape(&arena->allocator, str("\n\r\v\bdf asdfasdf"));
    str_debug(escaped);

    arena_release(arena);
    tctx_release();

    return 0;
}
