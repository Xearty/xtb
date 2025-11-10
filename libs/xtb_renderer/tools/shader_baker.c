#include <xtb_core/str.h>
#include <xtb_os/os.h>
#include <xtb_core/thread_context.h>
#include <xtb_core/core.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/panic.h>
#include <xtb_core/contract.h>
#include <xtb_core/str_buffer.h>

String ident_from_path(Allocator *allocator, String path)
{
    String base = path_strip_extension(path_basename(path));
    return str_concat(allocator, base, str("_source"));
}

void append_shader_source(StringBuffer *builder, String ident, String source)
{
    TempArena scratch = scratch_begin_no_conflicts();
    Allocator *allocator = &scratch.arena->allocator;

    source = str_trim(source);

    String prologue = str_format(allocator, "const char *%s = \"\"\n", ident.str);
    str_buffer_push_back(builder, prologue);

    StringList lines = str_split_by_lines(allocator, source);

    IterateList(lines, StringListNode, line)
    {
        str_buffer_push_back_cstring(builder, "   \"");
        str_buffer_push_back(builder, line->string);
        str_buffer_push_back_cstring(builder, "\\n\"");

        if (line->next)
        {
            str_buffer_push_back_char(builder, '\n');
        }
    }

    str_buffer_push_back_cstring(builder, ";\n\n");

    scratch_end(scratch);
}

int main(int argc, char **argv)
{
    if (argc != 3)
    {
        fprintf(stderr, "Program expects to be passed <shaders_dir> and <out_header_path>\n");
        return 1;
    }

    xtb_init(argc, argv);
    ThreadContext tctx;

    tctx_init_and_equip(&tctx);

    String shaders_dir = cstr(argv[1]);
    String out = cstr(argv[2]);

    Arena *permanent_arena = arena_new(Kilobytes(4));

    if (!os_create_directory(str("generated")))
    {
        panic("Could not create directory \"generated\"");
    }

    StringBuffer builder = str_buffer_new(&permanent_arena->allocator, 0);

    DirectoryList shader_paths = os_list_directory(&permanent_arena->allocator, shaders_dir);

    IterateList(shader_paths, DirectoryListNode, shader_file)
    {
        if (shader_file->type != FT_REGULAR) continue;

        TempArena scratch = scratch_begin_no_conflicts();
        Allocator *scratch_allocator = &scratch.arena->allocator;

        String ident = ident_from_path(scratch_allocator, shader_file->path);
        String source = os_read_entire_file(scratch_allocator, shader_file->path);

        if (str_is_invalid(source))
        {
            panic("Could not read %s", shader_file->path.str);
        }

        append_shader_source(&builder, ident, source);
        scratch_end(scratch);
    }

    usize bytes_written = os_write_entire_file(out, builder.data, builder.size);
    if (bytes_written != builder.size)
    {
        panic("Failed writing to %s", out);
    }

    tctx_release();

    return 0;
}
