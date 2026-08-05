// expected: unsupported public static unmanaged operation
module xtb.tests.compile_fail.ambiguous_static;

import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.memory : Allocator;

nothrow @nogc:

struct BadStorage
{
nothrow @nogc:
    @disable this(this);
    void deinit(Allocator*) {}
    void resetAndRelease(Allocator*) {}
    static int ambiguous(scope BadStorage* storage)
    {
        return storage is null ? 0 : 1;
    }
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
