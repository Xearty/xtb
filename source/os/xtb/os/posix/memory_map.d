module xtb.os.posix.memory_map;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import core.sys.posix.sys.mman : MAP_FAILED, MAP_PRIVATE, PROT_READ, mmap, munmap;
import xtb.os.error : OsError, OsErrorKind;
import xtb.os.handle : NativeHandle;
import xtb.os.posix.error : lastError;
import xtb.os.posix.handle : fileDescriptor;

/// Maps `length` bytes from an already-open native handle read-only.
OsError mapReadOnly(
    NativeHandle handle,
    size_t length,
    void** outputAddress,
) @system
{
    version (XTB_Checked)
        require(outputAddress !is null, "mapping output pointer is null");
    *outputAddress = null;
    if (!handle.valid || length == 0)
        return OsError(OsErrorKind.invalidArgument, 0);

    void* address = mmap(
        null,
        length,
        PROT_READ,
        MAP_PRIVATE,
        fileDescriptor(handle),
        0,
    );
    if (address == MAP_FAILED)
        return lastError();
    *outputAddress = address;
    return OsError.init;
}

/// Releases a mapping previously returned by `mapReadOnly`.
OsError unmap(void* address, size_t length) @system
{
    if (address is null || length == 0)
        return OsError.init;
    return munmap(address, length) == 0 ? OsError.init : lastError();
}
