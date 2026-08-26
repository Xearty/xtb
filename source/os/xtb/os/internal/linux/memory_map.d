module xtb.os.internal.linux.memory_map;

nothrow @nogc:

import core.sys.posix.fcntl : O_RDONLY, open;
import core.sys.posix.sys.mman : MAP_FAILED, MAP_PRIVATE, PROT_READ, mmap, munmap;
import core.sys.posix.sys.stat : fstat, stat_t;
import core.sys.posix.unistd : close;
import xtb.string : StringBuf;
import xtb.thread_context : ScratchScope;
import xtb.os.error : OsError, OsErrorKind, lastError;
import xtb.os.path : Path;

package(xtb.os) OsError unmapImpl(void* address, size_t length) @system
{
    return munmap(address, length) == 0 ? OsError.init : lastError();
}

package(xtb.os) OsError mapReadOnlyImpl(
    Path path,
    void** outputAddress,
    size_t* outputLength,
) @system
{
    ScratchScope scratch = ScratchScope.acquire();
    StringBuf native = StringBuf.fromString(scratch.allocator, path.view);
    const descriptor = open(native.checkedCString, O_RDONLY);
    if (descriptor < 0)
        return lastError();
    stat_t information;
    if (fstat(descriptor, &information) != 0)
    {
        const error = lastError();
        close(descriptor);
        return error;
    }
    if (information.st_size == 0)
    {
        close(descriptor);
        return OsError.init;
    }
    if (information.st_size < 0 || cast(ulong) information.st_size > size_t.max)
    {
        close(descriptor);
        return OsError(OsErrorKind.invalidArgument, 0);
    }
    const length = cast(size_t) information.st_size;
    void* address = mmap(null, length, PROT_READ, MAP_PRIVATE, descriptor, 0);
    const error = address == MAP_FAILED ? lastError() : OsError.init;
    close(descriptor);
    if (error.failed)
        return error;
    *outputAddress = address;
    *outputLength = length;
    return OsError.init;
}
