#include <xtb_core/linked_list.h>
#include <xtb_core/core.h>
#include <xtb_os/os.h>
#include <stdio.h>
#include <stdlib.h>

#include <xtb_allocator/allocator.h>

typedef struct PermissionsBuffer
{
    char buf[10];
} PermissionsBuffer;

PermissionsBuffer get_permissions_str(const char *filepath)
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

    XTB_Allocator allocator = xtb_malloc_allocator();

    XTB_Directory_List list = xtb_os_list_directory_recursively(allocator, "./libs");

    for (XTB_Directory_Listing_Node *entry = list.head; entry != NULL; entry = entry->next)
    {
        printf("[%s] [%s] %s\n", get_permissions_str(entry->path).buf, ft_to_str(entry->type), entry->path);
    }

    xtb_os_free_directory_list(allocator, &list);

    return 0;
}
