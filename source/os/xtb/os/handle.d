module xtb.os.handle;

nothrow @nogc:

/// Opaque native resource handle exchanged across low-level XTB boundaries.
///
/// Domain packages should pass this value through without depending on its
/// platform representation. Platform-specific `xtb.os.*` modules provide the
/// native adapters for their target.
struct NativeHandle
{
nothrow @nogc:

    private enum size_t invalidValue = size_t.max;
    private size_t value_ = invalidValue;

    bool valid() const pure @safe
    {
        return value_ != invalidValue;
    }

    package(xtb.os) static NativeHandle fromNativeValue(
        size_t value,
    ) pure @safe
    {
        return NativeHandle(value);
    }

    package(xtb.os) size_t nativeValue() const pure @safe
    {
        return value_;
    }
}

unittest
{
    NativeHandle handle;
    assert(!handle.valid);
}
