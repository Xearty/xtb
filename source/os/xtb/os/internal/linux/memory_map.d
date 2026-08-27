module xtb.os.internal.linux.memory_map;

nothrow @nogc:

import core.sys.posix.sys.mman : MAP_FAILED, MAP_PRIVATE, PROT_READ, mmap, munmap;
import xtb.os.error : OsError, lastError;
import xtb.os.handle : NativeHandle;

package(xtb.os) OsError unmapImpl(void* address, size_t length) @system
{
    return munmap(address, length) == 0 ? OsError.init : lastError();
}

package(xtb.os) OsError mapReadOnlyImpl(
    NativeHandle handle,
    size_t length,
    void** outputAddress,
) @system
{
    void* address = mmap(null, length, PROT_READ, MAP_PRIVATE, handle.fileDescriptor, 0);
    if (address == MAP_FAILED)
        return lastError();
    *outputAddress = address;
    return OsError.init;
}
