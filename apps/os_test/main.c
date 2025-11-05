#include <xtb_core/linked_list.h>
#include <xtb_core/core.h>
#include <xtb_os/os.h>
#include <stdio.h>
#include <stdlib.h>

#include <xtb_allocator/allocator.h>
#include <xtb_core/arena.h>
#include <xtb_core/linked_list.h>

typedef struct PermissionsBuffer
{
    char buf[10];
} PermissionsBuffer;

PermissionsBuffer get_permissions_str(XTB_String8 filepath)
{
    PermissionsBuffer perm = {};
    perm.buf[0] = xtb_os_file_has_execute_permission(filepath) ? 'x' : '-';
    perm.buf[1] = xtb_os_file_has_read_permission(filepath) ? 'r' : '-';
    perm.buf[2] = xtb_os_file_has_write_permission(filepath) ? 'w' : '-';
    return perm;
}

const char *ft_to_str(XTB_File_Type ft)
{
    switch (ft)
    {
        case XTB_FT_REGULAR: return "Regular";
        case XTB_FT_DIRECTORY: return "Directory";
        case XTB_FT_SYMLINK: return "Symbolic Link";
        default: return "Unknown";
    }
}

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    XTB_Arena *arena = xtb_arena_new(XTB_Kilobytes(4));
    XTB_Allocator allocator = xtb_arena_allocator(arena);

    XTB_Directory_List list = xtb_os_list_directory_recursively(allocator, xtb_str8_lit("./libs/"));

    for (XTB_Directory_Listing_Node *entry = list.head; entry != NULL; entry = entry->next)
    {
        printf("[%s] [%s] %s\n", get_permissions_str(entry->path).buf, ft_to_str(entry->type), entry->path.str);
    }

    xtb_os_copy_file(xtb_str8_lit("asd"), xtb_str8_lit("asd2"));

    xtb_os_free_directory_list(allocator, &list);

    XTB_String8 filepath = xtb_str8_lit("./apps/os_test/main.c");
    XTB_String8 file_content = xtb_os_read_entire_file(filepath);

    XTB_String8_List lines = xtb_str8_list_split_by_lines(allocator, file_content);

    XTB_IterateList(lines, XTB_String8_List_Node, line, {
        XTB_String8_List tokens = xtb_str8_list_split_by_whitespace(allocator, line->string);
        XTB_String8 joined = xtb_str8_list_join_char_sep(allocator, tokens, '&');
        xtb_str8_debug(joined);
    });

    xtb_arena_drop(arena);

    return 0;
}
