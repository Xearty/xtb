module xtb.os.internal.unsupported.memory_map;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.string : String;

package(xtb.os) OsError unmapImpl(void*, size_t) @system
{
    return unsupported();
}

package(xtb.os) OsError mapReadOnlyImpl(String, void**, size_t*) @system
{
    return unsupported();
}
