#include <xtb_core/linked_list.h>
#include <xtb_core/core.h>
#include <xtb_os/os.h>
#include <stdio.h>

#include <xtb_allocator/allocator.h>
#include <xtb_core/arena.h>
#include <xtb_core/linked_list.h>
#include <xtb_core/thread_context.h>

typedef struct PermissionsBuffer
{
    char buf[10];
} PermissionsBuffer;

PermissionsBuffer get_permissions_str(String8 filepath)
{
    PermissionsBuffer perm = {};
    perm.buf[0] = os_file_has_execute_permission(filepath) ? 'x' : '-';
    perm.buf[1] = os_file_has_read_permission(filepath) ? 'r' : '-';
    perm.buf[2] = os_file_has_write_permission(filepath) ? 'w' : '-';
    return perm;
}

const char *ft_to_str(File_Type ft)
{
    switch (ft)
    {
        case XTB_FT_REGULAR: return "Regular";
        case XTB_FT_DIRECTORY: return "Directory";
        case XTB_FT_SYMLINK: return "Symbolic Link";
        case XTB_FT_CHAR_DEVICE: return "Character Device";
        case XTB_FT_BLOCK_DEVICE: return "Block Device";
        case XTB_FT_FIFO: return "FIFO";
        case XTB_FT_SOCKET: return "Socket";
        default: return "Unknown";
    }
}

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    Thread_Context tctx;
    tctx_init_and_equip(&tctx);

    Arena *arena = arena_new(XTB_Kilobytes(4));

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
    // XTB_String8 filepath = xtb_str8_lit("./apps/os_test/main.c");
    // XTB_String8 file_content = xtb_os_read_entire_file(filepath);
    //
    // XTB_String8_List lines = xtb_str8_split_by_lines(allocator, file_content);
    //
    // XTB_IterateList(lines, XTB_String8_List_Node, line, {
    //     XTB_String8_List tokens = xtb_str8_split_by_whitespace(allocator, line->string);
    //     XTB_String8 joined = xtb_str8_list_join_char_sep(allocator, tokens, '&');
    //     xtb_str8_debug(joined);
    // });

    xtb_scratch_scope_no_conflicts(scratch)
    {
        String8 path = str8_lit("apps ");
        path = str8_trunc_right(path, 1);

        XTB_Directory_List list = os_list_directory(&scratch.arena->allocator, path);
        XTB_IterateList(list, XTB_Directory_Listing_Node, node)
        {
            XTB_File_Type ft = os_get_file_type(node->path);
            const char *ft_str = ft_to_str(ft);
            bool is_dir = os_file_is_directory(node->path);
            printf("%s %s %s\n", ft_str, node->path.str, is_dir ? "true" : "false");
        }
    }

    {
        String8 path = str8_lit("apps/CMakeLists.txt");
        String8 real = os_real_path(&arena->allocator, path);
        str8_debug(real);
    }

    arena_release(arena);

    tctx_release();

    return 0;
}
