// expected: Storage* output must be scope
module xtb.tests.compile_fail.nonscope_output;

import xtb.core.internal.managed_container_adapter : ManagedContainerAdapter;
import xtb.core.memory : Allocator;

nothrow @nogc:

struct BadStorage
{
nothrow @nogc:
    @disable this(this);
    void deinit(Allocator*) {}
    void resetAndRelease(Allocator*) {}
    static bool tryBad(Allocator*, BadStorage*) { return false; }
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
