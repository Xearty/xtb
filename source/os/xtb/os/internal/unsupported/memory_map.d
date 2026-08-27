module xtb.os.internal.unsupported.memory_map;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.os.handle : NativeHandle;

package(xtb.os) OsError unmapImpl(void*, size_t) @system
{
    return unsupported();
}

package(xtb.os) OsError mapReadOnlyImpl(
    NativeHandle,
    size_t,
    void**,
) @system
{
    return unsupported();
}
