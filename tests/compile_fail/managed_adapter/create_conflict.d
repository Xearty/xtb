// expected: .create conflicts with generated managed create
module xtb.tests.compile_fail.create_conflict;

import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.memory : Allocator;

nothrow @nogc:

struct BadStorage
{
nothrow @nogc:
    @disable this(this);
    void deinit(Allocator*) {}
    void resetAndRelease(Allocator*) {}
    static BadStorage create() { return BadStorage.init; }
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
