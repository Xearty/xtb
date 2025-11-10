#include <xtb_core/linked_list.h>
#include <xtb_core/core.h>
#include <xtb_os/os.h>
#include <stdio.h>

#include <xtb_core/arena.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/thread_context.h>

typedef struct PermissionsBuffer
{
    char buf[10];
} PermissionsBuffer;

PermissionsBuffer get_permissions_str(String filepath)
{
    PermissionsBuffer perm = {};
    perm.buf[0] = os_file_has_execute_permission(filepath) ? 'x' : '-';
    perm.buf[1] = os_file_has_read_permission(filepath) ? 'r' : '-';
    perm.buf[2] = os_file_has_write_permission(filepath) ? 'w' : '-';
    return perm;
}

const char *ft_to_str(FileType ft)
{
    switch (ft)
    {
        case FT_REGULAR: return "Regular";
        case FT_DIRECTORY: return "Directory";
        case FT_SYMLINK: return "Symbolic Link";
        case FT_CHAR_DEVICE: return "Character Device";
        case FT_BLOCK_DEVICE: return "Block Device";
        case FT_FIFO: return "FIFO";
        case FT_SOCKET: return "Socket";
        default: return "Unknown";
    }
}

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    ThreadContext tctx;
    tctx_init_and_equip(&tctx);

    Arena *arena = arena_new(Kilobytes(4));

    // XTB_Directory_List list = xtb_os_list_directory_recursively(allocator, xtb_str8_lit("./libs/"));
    //
    // for (XTB_Directory_Listing_Node *entry = list.head; entry != NULL; entry = entry->next)
    // {
    //     printf("[%s] [%s] %s\n", get_permissions_str(entry->path).buf, ft_to_str(entry->type), entry->path.str);
    // }
    //
    // xtb_os_copy_file(xtb_str8_lit("asd"), xtb_str8_lit("asd2"));
    //
    // xtb_os_free_directory_list(allocator, &list);
    //
    String filepath = str("./apps/os_test/main.c");
    String file_content = os_read_entire_file(allocator_get_heap(), filepath);
    str_debug(file_content);

    // XTB_String8_List lines = xtb_str8_split_by_lines(allocator, file_content);
    //
    // XTB_IterateList(lines, XTB_String8_List_Node, line, {
    //     XTB_String8_List tokens = xtb_str8_split_by_whitespace(allocator, line->string);
    //     XTB_String8 joined = xtb_str8_list_join_char_sep(allocator, tokens, '&');
    //     xtb_str8_debug(joined);
    // });

    scratch_scope_no_conflicts(scratch)
    {
        String path = str("apps ");
        path = str_trunc_right(path, 1);

        DirectoryList list = os_list_directory(&scratch.arena->allocator, path);
        IterateList(list, DirectoryListNode, node)
        {
            FileType ft = os_get_file_type(node->path);
            const char *ft_str = ft_to_str(ft);
            bool is_dir = os_file_is_directory(node->path);
            printf("%s %s %s\n", ft_str, node->path.str, is_dir ? "true" : "false");
        }
    }

    {
        String path = str("apps/CMakeLists.txt");
        String real = os_real_path(&arena->allocator, path);
        str_debug(real);
    }

    arena_release(arena);

    tctx_release();

    return 0;
}
