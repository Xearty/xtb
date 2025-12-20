#include <xtb_core/string.h>
#include <xtb_os/os.h>
#include <xtb_core/thread_context.h>
#include <xtb_core/core.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/panic.h>
#include <xtb_core/contract.h>

using namespace xtb;

#define HEADER_GUARD_NAME "XTB_RENDERER_GENERATED_SHADERS_HEADER"

String ident_from_path(Allocator *allocator, String path)
{
    return path
        .strip_extension()
        .basename()
        .concat("_source", allocator);
    // String base = path_strip_extension(path_basename(path));
    // return str_concat(allocator, base, "_source");
}

void append_shader_source(StringBuf& builder, String ident, String source)
{
    ScratchScope scratch(builder.allocator());
    Allocator *allocator = &scratch->allocator;

    source = source.trim();

    String prologue = String::format(allocator, "const char *%s = \"\"\n", ident.data());
    builder.append(prologue);

    StringList lines = source.split_by_lines(allocator);

    IterateList(&lines)
    {
        builder.append("   \"");
        builder.append(it->string);
        builder.append("\\n\"");

        if (it->next)
        {
            builder.append('\n');
        }
    }

    builder.append(";\n\n");
}

int main(int argc, char **argv)
{
    if (argc != 3)
    {
        fprintf(stderr, "Program expects to be passed <shaders_dir> and <out_header_path>\n");
        return 1;
    }

    xtb::init(argc, argv);
    ThreadContextScope tctx;

    String shaders_dir = String::from_cstr(argv[1]);
    String out = String::from_cstr(argv[2]);

    Arena *permanent_arena = arena_new(Kilobytes(4));

    if (!os::create_directory("generated"))
    {
        panic("Could not create directory \"generated\"");
    }

    StringBuf builder = StringBuf::init(&permanent_arena->allocator);

    os::DirectoryList shader_paths = os::list_directory(&permanent_arena->allocator, shaders_dir);

    builder.append("#ifndef " HEADER_GUARD_NAME "\n#define " HEADER_GUARD_NAME "\n\n");

    IterateList(&shader_paths)
    {
        auto shader_file = it;
        if (shader_file->type != os::FileType::Regular) continue;

        ScratchScope scratch;
        Allocator *scratch_allocator = &scratch->allocator;

        String ident = ident_from_path(scratch_allocator, shader_file->path);
        String source = os::read_entire_file(scratch_allocator, shader_file->path);

        if (source.is_invalid())
        {
            panic("Could not read %s", shader_file->path.data());
        }

        append_shader_source(builder, ident, source);
    }

    builder.append("#endif // " HEADER_GUARD_NAME);

    isize bytes_written = os::write_entire_file(out, builder.data(), builder.size());
    if (bytes_written != builder.size())
    {
        panic("Failed writing to %s", out);
    }

    return 0;
}
