module xtb.os.internal.unsupported.memory_map;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.os.path : Path;

package(xtb.os) OsError unmapImpl(void*, size_t) @system
{
    return unsupported();
}

package(xtb.os) OsError mapReadOnlyImpl(Path, void**, size_t*) @system
{
    return unsupported();
}
