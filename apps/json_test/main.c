#include <stdio.h>
#include <string.h>
#include <xtb_json/json.h>
#include <xtb_ansi/ansi.h>
#include <readline/readline.h>
#include <readline/history.h>
#include <xtb_allocator/arena.h>
#include <xtb_core/core.h>

bool starts_with(const char *str, const char *prefix) {
    size_t len = strlen(prefix);
    return strncmp(str, prefix, len) == 0;
}

char* trim_cstring(XTB_Arena *arena, const char *cstr)
{
    const char *begin_ptr = cstr;
    while (isspace(*begin_ptr)) begin_ptr++;

    const char *end_ptr = cstr + strlen(cstr);
    while (begin_ptr < end_ptr && (isspace(*end_ptr) || *end_ptr == '\0')) end_ptr--;;
    end_ptr++;

    int len = end_ptr - begin_ptr;
    char *buf = PushArray(arena, char, len + 1);
    strncpy(buf, begin_ptr, len);
    return buf;
}

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    if (argc > 2)
    {
        fprintf(stderr, "Usage: %s <file>\n", argv[0]);
        return 1;
    }

    const char *json_filepath = "./apps/json_test/test.json";
    if (argc == 2)
    {
        json_filepath = argv[1];
    }

    XTB_JSON_Value *toplevel_value = xtb_json_parse_file(xtb_str8_cstring(json_filepath));
    XTB_Arena *frame_arena = xtb_arena_new(XTB_MEGABYTES(4));

    char *input = NULL;
    size_t size = 0;
    const char *prompt = "\nxtb_json> ";

    while ((input = readline(prompt)) != NULL)
    {
        xtb_arena_clear(frame_arena);

        if (input[0] == '\0')
        {
            free(input);
            continue;
        }
        else
        {
            add_history(input);
        }

        if (starts_with(input, ":p "))
        {
            const char *query = input + strlen(":p ");
            XTB_JSON_Value *value = xtb_json_query(toplevel_value, query);

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
        else if (starts_with(input, ":t "))
        {
            const char *query = input + strlen(":t ");
            XTB_JSON_Value *value = xtb_json_query(toplevel_value, query);

            if (value)
            {
                fprintf(stderr, "%s\n", xtb_json_get_type_string(value));
            }
            else
            {
                xtb_ansi_print_red(stderr, "Could not find node\n");
            }
        }
        else if (starts_with(input, ":l "))
        {
            const char *filepath = input + strlen(":l ");
            char *trimmed = trim_cstring(frame_arena, filepath);

            XTB_JSON_Value *value = xtb_json_parse_file(xtb_str8_cstring(trimmed));
            if (value)
            {
                // Free the old value
                toplevel_value = value;
                json_filepath = filepath;
                xtb_ansi_print_bright_green(stderr, "Loaded \"%s\"\n", trimmed);
            }
            else
            {
                xtb_ansi_print_red(stderr, "Could not load \"%s\", \"%s\" is preserved\n", filepath, json_filepath);
            }
        }
        else if (starts_with(input, ":c"))
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
        else if (starts_with(input, ":h"))
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
        else if (starts_with(input, ":q"))
        {
            return 0;
        }
        else
        {
            xtb_ansi_print_red(stderr, "Invalid command\n");
        }

        free(input);
    }

    xtb_arena_drop(frame_arena);

    return 0;
}

