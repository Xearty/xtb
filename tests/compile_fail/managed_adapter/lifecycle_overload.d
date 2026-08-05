// expected: ReleasedStorage requires Storage.deinit(Allocator*)
module xtb.tests.compile_fail.lifecycle_overload;

import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.memory : Allocator;

nothrow @nogc:

struct BadStorage
{
    @disable this(this);
    void deinit(Allocator*) {}
    void deinit(Allocator*, int) {}
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
