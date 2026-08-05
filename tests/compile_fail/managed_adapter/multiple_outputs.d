// expected: unsupported public static unmanaged operation
module xtb.tests.compile_fail.multiple_outputs;

import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.memory : Allocator;

nothrow @nogc:

struct BadStorage
{
nothrow @nogc:
    @disable this(this);
    void deinit(Allocator*) {}
    void resetAndRelease(Allocator*) {}
    static bool tryBad(
        Allocator*,
        scope BadStorage*,
        scope BadStorage*,
    ) { return false; }
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
