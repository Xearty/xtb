#include "xtb_allocator/malloc.h"
#include "xtb_core/str.h"
#include <stdio.h>
#include <string.h>
#include <xtb_json/json.h>
#include <xtb_ansi/ansi.h>
#include <readline/readline.h>
#include <readline/history.h>
#include <xtb_core/arena.h>
#include <xtb_core/core.h>
#include <xtb_core/thread_context.h>

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    Thread_Context tctx;
    xtb_tctx_init_and_equip(&tctx);

    if (argc > 2)
    {
        fprintf(stderr, "Usage: %s <file>\n", argv[0]);
        return 1;
    }

    XTB_Allocator gpa = xtb_malloc_allocator();

    XTB_String8 json_filepath = xtb_str8_lit_copy(gpa, "./apps/json_test/test.json");
    if (argc == 2)
    {
        json_filepath = xtb_str8_lit_copy(gpa, argv[1]);
    }

    XTB_JSON_Value *toplevel_value = xtb_json_parse_file(json_filepath);
    XTB_Arena *frame_arena = xtb_arena_new(XTB_Megabytes(4));
    XTB_Allocator frame_allocator = xtb_arena_allocator(frame_arena);

    char *input_cstring = NULL;
    size_t size = 0;
    const char *prompt = "\nxtb_json> ";

    while ((input_cstring = readline(prompt)) != NULL)
    {
        XTB_String8 input = xtb_str8_cstring(input_cstring);

        xtb_arena_clear(frame_arena);

        if (input.str[0] == '\0')
        {
            free(input.str);
            continue;
        }
        else
        {
            add_history(input.str);
        }

        if (xtb_str8_starts_with_lit(input, ":p"))
        {
            XTB_String8 query = xtb_str8_trunc_left(input, 3);
            XTB_JSON_Value *value = xtb_json_query(toplevel_value, query.str);

            if (value)
            {
                xtb_json_pretty_print_value(value, 4, stderr);
                fprintf(stderr, "\n");
            }
            else
            {
                xtb_ansi_print_red(stderr, "Could not find node\n");
            }
        }
        else if (xtb_str8_starts_with_lit(input, ":t "))
        {
            XTB_String8 query = xtb_str8_trunc_left(input, 3);
            XTB_JSON_Value *value = xtb_json_query(toplevel_value, query.str);

            if (value)
            {
                fprintf(stderr, "%s\n", xtb_json_get_type_string(value));
            }
            else
            {
                xtb_ansi_print_red(stderr, "Could not find node\n");
            }
        }
        else if (xtb_str8_starts_with_lit(input, ":l "))
        {
            XTB_String8 filepath = xtb_str8_trunc_left(input, 3);
            filepath = str8_trim(filepath);

            XTB_JSON_Value *value = xtb_json_parse_file(filepath);
            if (value)
            {
                toplevel_value = value;
                xtb_str8_free(gpa, json_filepath);
                json_filepath = xtb_str8_copy(gpa, filepath);
                xtb_ansi_print_bright_green(stderr, "Loaded \"%s\"\n", filepath.str);
            }
            else
            {
                xtb_ansi_print_red(stderr, "Could not load \"%.*s\", \"%.*s\" is preserved\n",
                        filepath.len, filepath.str,
                        json_filepath.len, json_filepath.str);
            }
        }
        else if (xtb_str8_starts_with_lit(input, ":c"))
        {
            const char *cwd = getenv("PWD");
            if (cwd)
            {
                xtb_ansi_print_bright_green(stderr, "\"%s\"\n", cwd);
            }
            else
            {
                xtb_ansi_print_red(stderr, "Could not read $CWD\n");
            }
        }
        else if (xtb_str8_starts_with_lit(input, ":h"))
        {
            const char *help_message = ""
                "Interactive commands:\n"
                "    :l <filepath>          load a json file relative to $CWD\n"
                "    :c <filepath>          print $CWD\n"
                "    :p <json path query>   print json value at path\n"
                "    :t <json path query>   print the type of the json value at path\n"
                "    :q                     quit the interactive prompt\n"
                "\n";

            xtb_ansi_print_bright_yellow(stderr, help_message);
        }
        else if (xtb_str8_starts_with_lit(input, ":q"))
        {
            return 0;
        }
        else
        {
            xtb_ansi_print_red(stderr, "Invalid command\n");
        }

        free(input.str);
    }

    arena_release(frame_arena);

    tctx_release();

    return 0;
}

