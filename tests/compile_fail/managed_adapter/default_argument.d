// expected: uses a default argument
module xtb.tests.compile_fail.default_argument;

import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.memory : Allocator;

nothrow @nogc:

struct BadStorage
{
nothrow @nogc:
    @disable this(this);
    void deinit(Allocator*) {}
    void resetAndRelease(Allocator*) {}
    void bad(int value = 1) {}
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
