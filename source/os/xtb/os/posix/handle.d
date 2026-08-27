module xtb.os.posix.handle;

nothrow @nogc:

import xtb.os.handle : NativeHandle;

/// Wraps a POSIX file descriptor as an opaque XTB native handle.
NativeHandle fromFileDescriptor(int descriptor) pure @safe
{
    return descriptor >= 0
        ? NativeHandle.fromNativeValue(cast(size_t) descriptor) : NativeHandle.init;
}

/// Returns the POSIX file descriptor represented by `handle`, or -1 if invalid.
int fileDescriptor(NativeHandle handle) pure @safe
{
    return handle.valid ? cast(int) handle.nativeValue : -1;
}

unittest
{
    NativeHandle handle = fromFileDescriptor(0);
    assert(handle.valid);
    assert(fileDescriptor(handle) == 0);
    assert(!fromFileDescriptor(-1).valid);
    assert(fileDescriptor(NativeHandle.init) == -1);
}
