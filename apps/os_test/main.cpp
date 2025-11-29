#include <xtb_core/linked_list.h>
#include <xtb_core/core.h>
#include <xtb_os/os.h>
#include <iostream>

#include <xtb_core/arena.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/thread_context.h>

#include <xtb_ansi/ansi.h>

using namespace xtb;

struct PermissionsBuffer
{
    char buf[10];
};

PermissionsBuffer get_permissions_str(String filepath)
{
    PermissionsBuffer perm = {};
    perm.buf[0] = os::file_has_execute_permission(filepath) ? 'x' : '-';
    perm.buf[1] = os::file_has_read_permission(filepath) ? 'r' : '-';
    perm.buf[2] = os::file_has_write_permission(filepath) ? 'w' : '-';
    return perm;
}

const char *ft_to_str(os::FileType ft)
{
    switch (ft)
    {
        case os::FileType::Regular: return "Regular";
        case os::FileType::Directory: return "Directory";
        case os::FileType::Symlink: return "Symbolic Link";
        case os::FileType::CharDevice: return "Character Device";
        case os::FileType::BlockDevice: return "Block Device";
        case os::FileType::Fifo: return "FIFO";
        case os::FileType::Socket: return "Socket";
        default: return "Unknown";
    }
}

int main(int argc, char **argv)
{
    xtb::init(argc, argv);

    ThreadContextScope tctx;

    Arena *arena = arena_new(Kilobytes(4));

    // DirectoryList list = os_list_directory_recursively(allocator, str("./libs/"));
    //
    // for (DirectoryListNode *entry = list.head; entry != NULL; entry = entry->next)
    // {
    //     printf("[%s] [%s] %s\n", get_permissions_str(entry->path).buf, ft_to_str(entry->type), entry->path.str);
    // }
    //
    // os_copy_file(str("asd"), str("asd2"));

    // String filepath = "./apps/os_test/main.cpp";
    // String file_content = os::read_entire_file(allocator_get_heap(), filepath);
    // std::cout << file_content << std::endl;

    // StringList lines = str_split_by_lines(allocator, file_content);
    //
    // IterateList(lines, StringListNode, line)
    // {
    //     StringList tokens = str_split_by_whitespace(allocator, line->string);
    //     String joined = str_list_join_char_sep(allocator, tokens, '&');
    //     str_debug(joined);
    // });

    {
        ScratchScope scratch;
        String path = "apps ";
        path = path.trunc_right(1);

        os::DirectoryList list = os::list_directory(&scratch->allocator, path);
        IterateList(&list)
        {
            os::FileType ft = os::get_file_type(it->path);
            const char *ft_str = ft_to_str(ft);
            bool is_dir = os::file_is_directory(it->path);
            std::cout << ft_str << " " << it->path << " " << (is_dir ? "true" : "false") << std::endl;
        }
    }

    {
        String path = "apps/CMakeLists.txt";
        String real = os::real_path(&arena->allocator, path);
        std::cout << real << std::endl;
    }

    std::cout << "-------------------------------------------------------" << std::endl;
    {
        ScratchScope scratch;

        StringBuf b = StringBuf::init(&scratch->allocator);

        auto write_color_table = [&b, &scratch](const char* ident, const char* fmt) {
            b.append("static const char* ");
            b.append(String::from_cstr(ident));
            b.append("[] = {\n");

            for (i32 i = 0; i < 256; ++i)
            {
                ScratchScope entry_scratch(&scratch->allocator);
                b.append("    ");
                b.append(String::format(&entry_scratch->allocator, fmt, i));
                b.append(",\n");
            }
            b.append("};\n");
        };

        b.append("#ifndef XTB_ANSI_COLOR_8BIT\n");
        b.append("#define XTB_ANSI_COLOR_8BIT\n");
        write_color_table("ansi_foreground_colors_8bit", "\"\\e[38;5;%dm\"");
        write_color_table("ansi_background_colors_8bit", "\"\\e[48;5;%dm\"");
        b.append("#endif // XTB_ANSI_COLOR_8BIT");
    }

    arena_release(arena);

    return 0;
}
