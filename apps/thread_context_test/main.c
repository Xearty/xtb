#include <xtb_core/core.h>
#include <xtb_core/str.h>
#include <xtb_core/thread_context.h>

typedef struct SomeStruct
{
    int x;
    String name;
    struct { int x, y, z; } nested;
} SomeStruct;

void some_function_that_does_not_take_allocator()
{
    TempArena temp = scratch_begin(NULL, 0);

    printf("Initial arena offset = %zu\n", temp.arena->current_chunk->offset);

    SomeStruct *s = push_struct(temp.arena, SomeStruct);
    s->x = 42;
    s->name = str("Sasho e pich");
    s->nested.x = 1;
    s->nested.y = 2;
    s->nested.z = 3;

    printf("Later arena offset = %zu\n", temp.arena->current_chunk->offset);

    TempArena second_temp = scratch_begin(&temp.arena, 1);
    // Here I have another scratch space that is independent from the other

    String codetracer = str_copy(&second_temp.arena->allocator, str("codetracer"));
    str_debug(codetracer);
    printf("Second arena offset = %zu\n", second_temp.arena->current_chunk->offset);

    scratch_end(second_temp);

    scratch_end(temp);
}

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    ThreadContext tctx = {};
    tctx_init_and_equip(&tctx);

    some_function_that_does_not_take_allocator();
    some_function_that_does_not_take_allocator();

    tctx_release();

    return 0;
}
