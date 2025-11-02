#include <xtb_core/linked_list.h>
#include <xtb_core/core.h>
#include <xtb_os/os.h>
#include <stdio.h>
#include <stdlib.h>

#include <xtb_allocator/allocator.h>

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

    XTB_Arena *arena = xtb_arena_new(XTB_MEGABYTES(4));
    XTB_Allocator arena_allocator = xtb_arena_allocator(arena);

    XTB_Directory_List list = xtb_os_iterate_directory_recursively(arena_allocator, "./libs");

    for (XTB_Directory_Listing_Node *entry = list.head; entry != NULL; entry = entry->next)
    {
        printf("[%s] %s\n", ft_to_str(entry->type), entry->path);
    }

    xtb_arena_drop(arena);

    return 0;
}
