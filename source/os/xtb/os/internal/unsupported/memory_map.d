module xtb.os.internal.unsupported.memory_map;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;

package(xtb.os) OsError unmapImpl(void*, size_t) @system
{
    return unsupported();
}

package(xtb.os) OsError mapReadOnlyImpl(int, size_t, void**) @system
{
    return unsupported();
}
