#include <xtb_core/core.h>
#include "xtb_da/da.h"
#include <stdio.h>

XTB_DA_DEFINE_TYPE(Ints, int);

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    Ints ints = {};
    xtb_da_append(&ints, 1);
    xtb_da_append(&ints, 5);
    xtb_da_append(&ints, 3);
    xtb_da_append(&ints, 2);

    for (int i = 0; i < ints.count; ++i)
    {
        printf("items[%d] = %d\n", i, ints.items[i]);
    }

    return 0;
}

