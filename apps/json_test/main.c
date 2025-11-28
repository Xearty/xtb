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

    ThreadContext tctx;
    tctx_init_and_equip(&tctx);

    if (argc > 2)
    {
        fprintf(stderr, "Usage: %s <file>\n", argv[0]);
        return 1;
    }

    Allocator* gpa = allocator_get_heap();

    String json_filepath = str_copy(gpa, str("./apps/json_test/test.json"));
    if (argc == 2)
    {
        json_filepath = cstr_copy(gpa, argv[1]);
    }

    JsonValue *toplevel_value = json_parse_file(json_filepath);
    Arena *frame_arena = arena_new(Megabytes(4));

    char *input_cstring = NULL;
    const char *prompt = "\njson> ";

    while ((input_cstring = readline(prompt)) != NULL)
    {
        String input = cstr(input_cstring);

        arena_clear(frame_arena);

        if (input.str[0] == '\0')
        {
            free(input.str);
            continue;
        }
        else
        {
            add_history((char*)input.str);
        }

        if (str_starts_with_lit(input, ":p"))
        {
            String query = str_trunc_left(input, 3);
            JsonValue *value = json_query(toplevel_value, (char*)query.str);

            if (value)
            {
                json_pretty_print_value(value, 4, stderr);
                fprintf(stderr, "\n");
            }
            else
            {
                ansi_print_red(stderr, "Could not find node\n");
            }
        }
        else if (str_starts_with_lit(input, ":t "))
        {
            String query = str_trunc_left(input, 3);
            JsonValue *value = json_query(toplevel_value, (char*)query.str);

            if (value)
            {
                fprintf(stderr, "%s\n", json_get_type_string(value));
            }
            else
            {
                ansi_print_red(stderr, "Could not find node\n");
            }
        }
        else if (str_starts_with_lit(input, ":l "))
        {
            String filepath = str_trunc_left(input, 3);
            filepath = str_trim(filepath);

            JsonValue *value = json_parse_file(filepath);
            if (value)
            {
                toplevel_value = value;
                str_free(gpa, json_filepath);
                json_filepath = str_copy(gpa, filepath);
                ansi_print_bright_green(stderr, "Loaded \"%s\"\n", filepath.str);
            }
            else
            {
                ansi_print_red(stderr, "Could not load \"%.*s\", \"%.*s\" is preserved\n",
                        filepath.len, filepath.str,
                        json_filepath.len, json_filepath.str);
            }
        }
        else if (str_starts_with_lit(input, ":c"))
        {
            const char *cwd = getenv("PWD");
            if (cwd)
            {
                ansi_print_bright_green(stderr, "\"%s\"\n", cwd);
            }
            else
            {
                ansi_print_red(stderr, "Could not read $CWD\n");
            }
        }
        else if (str_starts_with_lit(input, ":h"))
        {
            const char *help_message = ""
                "Interactive commands:\n"
                "    :l <filepath>          load a json file relative to $CWD\n"
                "    :c <filepath>          print $CWD\n"
                "    :p <json path query>   print json value at path\n"
                "    :t <json path query>   print the type of the json value at path\n"
                "    :q                     quit the interactive prompt\n"
                "\n";

            ansi_print_bright_yellow(stderr, help_message);
        }
        else if (str_starts_with_lit(input, ":q"))
        {
            return 0;
        }
        else
        {
            ansi_print_red(stderr, "Invalid command\n");
        }

        free(input.str);
    }

    arena_release(frame_arena);

    tctx_release();

    return 0;
}

