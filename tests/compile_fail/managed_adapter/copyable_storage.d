// expected: non-copyable unmanaged storage
module xtb.tests.compile_fail.copyable_storage;

import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.memory : Allocator;

nothrow @nogc:

struct BadStorage
{
    void deinit(Allocator*) {}
    void resetAndRelease(Allocator*) {}
}

struct Bad
{
    alias Self = Bad;
    alias Storage = BadStorage;
private:
    Allocator* allocator_;
    Storage storage_;
public:
    mixin ManagedContainerAdapter!(Self, Storage);
}
