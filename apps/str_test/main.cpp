#include "xtb_core/stacktrace.h"
#include <xtb_core/core.h>
#include <xtb_core/string.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/arena.h>
#include <xtb_core/thread_context.h>
#include <xtb_core/contract.h>
#include <xtb_core/array.h>
#include <xtb_ansi/ansi.h>

using namespace xtb;

#include <iostream>

#include <stdio.h>

int main(int argc, char **argv)
{
    xtb::init(argc, argv);

    ThreadContextScope tctx;

    Arena *arena = arena_new(Kilobytes(4));

    String string = "hello";
    std::cout << string << std::endl;
    printf("length = %zu\n", string.len());

    // String dyn_string = str_copy(&arena->allocator, "hello there");
    String dyn_string = String("hello there").copy(&arena->allocator);
    printf("dyn_string = %s, length = %zu\n", dyn_string.data(), dyn_string.len());

    StringList str_list = {0};
    StringList::Node node1 = { "hello " };
    StringList::Node node2 = { "world" };

    SLLQueuePush(str_list.head, str_list.tail, &node1);
    SLLQueuePush(str_list.head, str_list.tail, &node2);

    String concatenated = str_list.join(&arena->allocator);
    std::cout << concatenated << std::endl;

    String test2 = "Nqkakuv dulug string";

    String sub_test2 = test2.substr(10, 5).copy(&arena->allocator);
    std::cout << "str = " << sub_test2 << ", len = " << sub_test2.len() << std::endl;

    TempArena temp = scratch_begin(NULL, 0);

    StringList list = {0};
    list.push_back("a", &temp.arena->allocator);
    list.push_back("b", &temp.arena->allocator);
    list.push_back("c", &temp.arena->allocator);
    list.push_back("d", &temp.arena->allocator);
    list.push_back("e", &temp.arena->allocator);

    String sep = ".";
    String joined = list.join_string_sep(sep, &arena->allocator);
    puts((char*)joined.data());

    if (joined == "a.b.c.d.e")
    {
        puts("The strings are equal");
    }
    else
    {
        puts("The strings are different");
    }

    String test3 = "Hello world";
    test3 = test3.trunc_left(3);
    test3 = test3.trunc_right(4);
    test3 = test3.copy(&temp.arena->allocator);
    puts((char*)test3.data());

    String test4 = "\t \n  First  \n \t  \t\t \r Second\n \t\t \r\n";
    String test5 = test4;
    test5 = test4.trim_left().copy(&temp.arena->allocator);
    printf("Left trimmed: \"%s\"\n", test5.data());

    test5 = test4.trim_right().copy(&temp.arena->allocator);
    printf("Right trimmed: \"%s\"\n", test5.data());

    test5 = test4.trim().copy(&temp.arena->allocator);
    printf("Trimmed both ways: \"%s\"\n", test5.data());

    String test6 = test4.trim().copy(&temp.arena->allocator);
    printf("Trimmed both ways copy: \"%s\"\n", test6.data());

    String char_split_str = "Very long string that contains multiple tokens";
    StringList char_split_list = char_split_str.split_by_char(' ', &temp.arena->allocator);
    String char_joined = char_split_list.join_string_sep("<sep>", &temp.arena->allocator);
    std::cout << char_joined << std::endl;

    String str_split_str = "Very long  string that contains  multiple tokens";
    StringList str_split_list = str_split_str.split_by_str("  ", &temp.arena->allocator);
    String str_joined = str_split_list.join_string_sep("---", &temp.arena->allocator);
    std::cout << str_joined << std::endl;

    String space_split_str = "\t\n\r\r\n Very \t long  \rstring\r\rthat contains \r \nmultiple \n\r\r\n\ttokens\t\n\t";
    StringList space_split_list = space_split_str.split_by_whitespace(&temp.arena->allocator);
    String space_joined = space_split_list.join_char_sep('-', &temp.arena->allocator);
    std::cout << space_joined << std::endl;

    String concatenated2 = space_split_list.join(&temp.arena->allocator);
    std::cout << concatenated2 << std::endl;

    scratch_end(temp);

    String formatted = String::format(&arena->allocator, "The answer is %d", 42);
    std::cout << formatted << std::endl;

    String head_tail = "head<>tail";
    String head = head_tail.head(4);
    String tail = head_tail.tail(4);
    std::cout << head_tail << std::endl;
    std::cout << head << std::endl;
    std::cout << tail << std::endl;

    if (!head_tail.starts_with("head"))
    {
        Assert(false);
    }

    if (!head_tail.ends_with("tail"))
    {
        Assert(false);
    }

    String concat = String("hello ").concat("world", &arena->allocator);
    std::cout << concat << std::endl;

    String str = "hello";
    str = str.concat(" world", &arena->allocator);
    std::cout << str << std::endl;

    puts("----------------------String Buffer------------------------");
    {
        TempArena scratch = scratch_begin(0, 0);

        // This will be allocated on the scratch arena
        StringBuf str_buffer = StringBuf::init(&scratch.arena->allocator);
        for (int i = 0; i < 10; ++i)
        {
            String hello = "hello";
            str_buffer.append(hello);
            str_buffer.append(" ");
            str_buffer.append("not ");
            str_buffer.append("world");
            str_buffer.append('!');
        }

        // This is allocated on the persistent arena
        String owned_str = str_buffer.detach();

        scratch_end(scratch);

        std::cout << owned_str << std::endl;
    }
    puts("-----------------------------------------------------------");

    String escaped = String("\n\r\v\bdf asdfasdf").escape(&arena->allocator);
    std::cout << escaped << std::endl;

    isize idx = String("asassdsaasssfd").find_last("ass");
    std::cout << "idx = " << idx << std::endl;

    arena_release(arena);

    return 0;
}
