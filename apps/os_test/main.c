#include <xtb_core/core.h>
#include <xtb_os/os.h>
#include <stdio.h>
#include <stdlib.h>

#include <xtb_allocator/allocator.h>

typedef struct Node
{
    int value;
    struct Node *next;
    struct Node *prev;
} Node;

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    XTB_Arena *arena = xtb_arena_new(XTB_MEGABYTES(4));
    XTB_Allocator arena_allocator = xtb_arena_allocator(arena);

    XTB_Directory_Listing_Node *entries = xtb_iterate_directory(arena_allocator, ".");
    for (XTB_Directory_Listing_Node *node = entries; node != NULL; node = node->next)
    {
        puts(node->value);
    }

    xtb_arena_drop(arena);

    return 0;
}
