module xtb.os.internal.linux.pipe;

nothrow @nogc:

import xtb.os.error : OsError, fromErrno, lastError;
import xtb.os.handle : NativeHandle;
import xtb.os.internal.pipe : NativePipeReadResult, NativePipeReadState,
    NativePipeWriteResult, NativePipeWriteState;
import xtb.types : u8;

package(xtb.os) OsError createPipeImpl(
    bool readerNonBlocking,
    bool writerNonBlocking,
    NativeHandle* readerHandle,
    NativeHandle* writerHandle,
) @system
{
    import core.sys.posix.fcntl : O_CLOEXEC;

    int[2] descriptors = [-1, -1];
    if (nativePipe2(descriptors.ptr, O_CLOEXEC) != 0)
        return lastError();

    OsError error;
    if (readerNonBlocking)
        error = setNonBlocking(descriptors[0]);
    if (error.succeeded && writerNonBlocking)
        error = setNonBlocking(descriptors[1]);
    if (error.failed)
    {
        cast(void) closeDescriptor(descriptors[0]);
        cast(void) closeDescriptor(descriptors[1]);
        return error;
    }

    *readerHandle = fromDescriptor(descriptors[0]);
    *writerHandle = fromDescriptor(descriptors[1]);
    return OsError.init;
}

package(xtb.os) OsError closeHandleImpl(NativeHandle handle) @system
{
    return closeDescriptor(toDescriptor(handle));
}

package(xtb.os) NativePipeReadResult readSomeImpl(
    NativeHandle handle,
    u8[] output,
) @system
{
    import core.stdc.errno : EAGAIN, EINTR, EWOULDBLOCK, errno;
    import core.sys.posix.unistd : read;

    for (;;)
    {
        const amount = read(toDescriptor(handle), output.ptr, output.length);
        if (amount > 0)
            return NativePipeReadResult(
                OsError.init,
                cast(size_t) amount,
                NativePipeReadState.data,
            );
        if (amount == 0)
            return NativePipeReadResult(
                OsError.init,
                0,
                NativePipeReadState.endOfFile,
            );
        if (errno == EINTR)
            continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK)
            return NativePipeReadResult(
                OsError.init,
                0,
                NativePipeReadState.wouldBlock,
            );
        return NativePipeReadResult(lastError(), 0, NativePipeReadState.data);
    }
}

package(xtb.os) NativePipeWriteResult writeSomeImpl(
    NativeHandle handle,
    scope const(u8)[] input,
) @system
{
    import core.stdc.errno : EAGAIN, EINTR, EPIPE, EWOULDBLOCK, errno;
    import core.sys.posix.signal : SIG_BLOCK, SIG_SETMASK, SIGPIPE,
        pthread_sigmask, sigaddset, sigemptyset, sigismember, sigpending,
        sigset_t, sigtimedwait;
    import core.sys.posix.time : timespec;
    import core.sys.posix.unistd : write;

    sigset_t blocked;
    sigset_t previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGPIPE);
    int code = pthread_sigmask(SIG_BLOCK, &blocked, &previous);
    if (code != 0)
        return NativePipeWriteResult(
            fromErrno(code),
            0,
            NativePipeWriteState.data,
        );

    sigset_t pending;
    if (sigpending(&pending) != 0)
    {
        const pendingError = lastError();
        pthread_sigmask(SIG_SETMASK, &previous, null);
        return NativePipeWriteResult(
            pendingError,
            0,
            NativePipeWriteState.data,
        );
    }
    const wasPending = sigismember(&pending, SIGPIPE) == 1;

    long amount;
    do
        amount = write(toDescriptor(handle), input.ptr, input.length);
    while (amount < 0 && errno == EINTR);
    const writeError = amount < 0 ? errno : 0;

    if (writeError == EPIPE && !wasPending)
    {
        timespec immediate;
        while (sigtimedwait(&blocked, null, &immediate) < 0 && errno == EINTR)
        {
        }
    }

    code = pthread_sigmask(SIG_SETMASK, &previous, null);
    if (code != 0)
        return NativePipeWriteResult(
            fromErrno(code),
            0,
            NativePipeWriteState.data,
        );
    if (amount >= 0)
        return NativePipeWriteResult(
            OsError.init,
            cast(size_t) amount,
            NativePipeWriteState.data,
        );
    if (writeError == EPIPE)
        return NativePipeWriteResult(
            OsError.init,
            0,
            NativePipeWriteState.peerClosed,
        );
    if (writeError == EAGAIN || writeError == EWOULDBLOCK)
        return NativePipeWriteResult(
            OsError.init,
            0,
            NativePipeWriteState.wouldBlock,
        );
    return NativePipeWriteResult(
        fromErrno(writeError),
        0,
        NativePipeWriteState.data,
    );
}

private NativeHandle fromDescriptor(int descriptor) pure @safe
{
    return NativeHandle.fromFileDescriptor(descriptor);
}

private int toDescriptor(NativeHandle handle) pure @safe
{
    return handle.fileDescriptor;
}

private OsError closeDescriptor(int descriptor) @system
{
    import core.sys.posix.unistd : nativeClose = close;

    return nativeClose(descriptor) == 0 ? OsError.init : lastError();
}

private extern (C) pragma(mangle, "pipe2")
int nativePipe2(int* descriptors, int flags);

private OsError setNonBlocking(int descriptor) @system
{
    import core.sys.posix.fcntl : F_GETFL, F_SETFL, O_NONBLOCK, fcntl;

    const flags = fcntl(descriptor, F_GETFL, 0);
    if (flags < 0)
        return lastError();
    return fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
        ? OsError.init : lastError();
}
