module xtb.os.memory_map;

import xtb.core.panic : require;
import xtb.core.string : StringBuf, checkedCString;
import xtb.core.thread_context : ScratchScope;
import xtb.core.types : u8;
import xtb.os.error : OsError, OsErrorKind, lastError, unsupported;
import xtb.os.path : Path;

struct MappedFile
{
    private void* address_;
    private size_t length_;

    @disable this(this);

    ~this() nothrow @nogc
    {
        deinit();
    }

    void deinit() nothrow @nogc
    {
        version (linux)
        {
            import core.sys.posix.sys.mman : munmap;

            if (address_ !is null)
                munmap(address_, length_);
        }
        address_ = null;
        length_ = 0;
    }

    const(u8)[] bytes() const return nothrow @system @nogc
    {
        return (cast(const(u8)*) address_)[0 .. length_];
    }

    bool empty() const pure nothrow @safe @nogc
    {
        return length_ == 0;
    }
}

OsError mapReadOnly(Path path, MappedFile* output) nothrow @system @nogc
{
    require(output !is null, "MappedFile output pointer is null");
    output.deinit();
    version (linux)
    {
        import core.sys.posix.fcntl : O_RDONLY, open;
        import core.sys.posix.sys.mman : MAP_FAILED, MAP_PRIVATE, PROT_READ, mmap;
        import core.sys.posix.sys.stat : fstat, stat_t;
        import core.sys.posix.unistd : close;

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
        output.address_ = address;
        output.length_ = length;
        return OsError.init;
    }
    else
        return unsupported();
}
