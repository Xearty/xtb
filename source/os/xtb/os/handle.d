module xtb.os.handle;

nothrow @nogc:

/// Opaque native resource handle exchanged across low-level XTB boundaries.
///
/// Domain packages should pass this value through without depending on its
/// platform representation. Platform-specific code may use the native adapters
/// exposed for its target.
struct NativeHandle
{
nothrow @nogc:

    private enum size_t invalidValue = size_t.max;
    private size_t value_ = invalidValue;

    bool valid() const pure @safe
    {
        return value_ != invalidValue;
    }

    version (Posix) static NativeHandle fromFileDescriptor(
        int descriptor,
    ) pure @safe
    {
        NativeHandle handle;
        if (descriptor >= 0)
            handle.value_ = cast(size_t) descriptor;
        return handle;
    }

    version (Posix) int fileDescriptor() const pure @safe
    {
        return valid ? cast(int) value_ : -1;
    }
}

unittest
{
    NativeHandle handle;
    assert(!handle.valid);

    version (Posix)
    {
        handle = NativeHandle.fromFileDescriptor(0);
        assert(handle.valid);
        assert(handle.fileDescriptor == 0);
        assert(!NativeHandle.fromFileDescriptor(-1).valid);
    }
}
