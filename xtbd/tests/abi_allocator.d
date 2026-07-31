module tests.abi_allocator;

import xtb.core.memory : Allocator, allocate, deallocate;

extern(C) Allocator* xtbd_test_c_allocator() nothrow @nogc;

extern(C) int main()
{
    Allocator* allocator = xtbd_test_c_allocator();
    int* value = allocator.allocate!int();
    if (value is null)
        return 1;
    *value = 42;
    const valid = *value == 42;
    allocator.deallocate(value);
    return valid ? 0 : 2;
}
