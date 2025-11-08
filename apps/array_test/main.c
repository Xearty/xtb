#include <xtb_core/core.h>
#include <xtb_core/array.h>
#include <xtb_core/thread_context.h>

#include <stdio.h>

typedef struct Test_Struct
{
    int x, y, z;
} Test_Struct;

typedef Array(Test_Struct) Test_Struct_Array;

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    Thread_Context tctx;
    tctx_init_and_equip(&tctx);

    Allocator *allocator = allocator_get_heap();

    Test_Struct_Array array = make_array(allocator);

    for (int i = 0; i < 5; i++)
    {
        Test_Struct st = {};
        st.x = 3 * i + 0;
        st.y = 3 * i + 1;
        st.z = 3 * i + 2;
        array_push(&array, st);
    }

    for (int i = 0; i < array.count; i++)
    {
        Test_Struct st = array.data[i];
        printf("item[%d] = (%d, %d, %d)\n", i, st.x, st.y, st.z);
    }

    tctx_release();
    return 0;
}
