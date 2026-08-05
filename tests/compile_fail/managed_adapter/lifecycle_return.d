// expected: .deinit must return void
module xtb.tests.compile_fail.lifecycle_return;

import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.memory : Allocator;

nothrow @nogc:

struct BadStorage
{
    @disable this(this);
    int deinit(Allocator*) { return 0; }
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
