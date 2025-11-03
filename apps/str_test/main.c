#include "xtb_allocator/malloc.h"
#include <xtb_core/core.h>
#include <xtb_str/str.h>

#include <stdio.h>

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    XTB_String8 string = xtb_str8_lit("hello");
    puts(string.str);
    printf("length = %zu\n", string.len);

    XTB_Allocator allocator = xtb_malloc_allocator();
    XTB_String8 dyn_string = xtb_str8_copy_lit(allocator, "hello there");
    printf("dyn_string = %s, length = %zu\n", dyn_string.str, dyn_string.len);
    xtb_str8_free(allocator, dyn_string);

    return 0;
}
