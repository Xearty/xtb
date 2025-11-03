#include <xtb_core/core.h>
#include <xtb_core/str.h>
#include <xtb_core/thread_context.h>

typedef struct SomeStruct
{
    int x;
    XTB_String8 name;
    struct { int x, y, z; } nested;
} SomeStruct;

void some_function_that_does_not_take_allocator()
{
    XTB_Temp_Arena temp = xtb_scratch_begin(NULL, 0);

    printf("Initial arena offset = %zu\n", temp.arena->current_chunk->offset);

    SomeStruct *s = xtb_push_struct(temp.arena, SomeStruct);
    s->x = 42;
    s->name = xtb_str8_lit("Sasho e pich");
    s->nested.x = 1;
    s->nested.y = 2;
    s->nested.z = 3;

    printf("Later arena offset = %zu\n", temp.arena->current_chunk->offset);

    XTB_Temp_Arena second_temp = xtb_scratch_begin(&temp.arena, 1);
    // Here I have another scratch space that is independent from the other

    XTB_Allocator allocator = xtb_arena_allocator(second_temp.arena);
    XTB_String8 codetracer = xtb_str8_copy(allocator, xtb_str8_lit("codetracer"));
    puts(codetracer.str);
    printf("Second arena offset = %zu\n", second_temp.arena->current_chunk->offset);

    xtb_scratch_end(second_temp);

    xtb_scratch_end(temp);
}

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    XTB_Thread_Context tctx = {};
    xtb_tctx_init_and_equip(&tctx);

    some_function_that_does_not_take_allocator();
    some_function_that_does_not_take_allocator();

    return 0;
}
