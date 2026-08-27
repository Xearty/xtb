module xtb.os.internal.linux.memory_map;

nothrow @nogc:

import core.sys.posix.sys.mman : MAP_FAILED, MAP_PRIVATE, PROT_READ, mmap, munmap;
import xtb.os.error : OsError, lastError;

package(xtb.os) OsError unmapImpl(void* address, size_t length) @system
{
    return munmap(address, length) == 0 ? OsError.init : lastError();
}

package(xtb.os) OsError mapReadOnlyImpl(
    int descriptor,
    size_t length,
    void** outputAddress,
) @system
{
    void* address = mmap(null, length, PROT_READ, MAP_PRIVATE, descriptor, 0);
    if (address == MAP_FAILED)
        return lastError();
    *outputAddress = address;
    return OsError.init;
}
