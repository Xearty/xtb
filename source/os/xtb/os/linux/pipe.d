module xtb.os.linux.pipe;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.os.error : OsError;
import xtb.os.posix.error : fromErrno, lastError;
import xtb.os.handle : NativeHandle;
import xtb.os.posix.handle : fileDescriptor, fromFileDescriptor;
import xtb.os.linux.signal : SignalMaskOperation, signalMask;
import xtb.types : u8;

enum PipeReadState : ubyte
{
    data,
    endOfFile,
    wouldBlock,
}

struct PipeReadResult
{
    OsError error;
    size_t transferred;
    PipeReadState state;
}

enum PipeWriteState : ubyte
{
    data,
    peerClosed,
    wouldBlock,
}

struct PipeWriteResult
{
    OsError error;
    size_t transferred;
    PipeWriteState state;
}

OsError createPipe(
    bool readerNonBlocking,
    bool writerNonBlocking,
    NativeHandle* readerHandle,
    NativeHandle* writerHandle,
) @system
{
    version (XTB_Checked)
    {
        require(readerHandle !is null, "pipe reader handle output is null");
        require(writerHandle !is null, "pipe writer handle output is null");
        require(readerHandle !is writerHandle, "pipe handle outputs must be distinct");
    }
    *readerHandle = NativeHandle.init;
    *writerHandle = NativeHandle.init;

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

OsError closeHandle(NativeHandle handle) @system
{
    if (!handle.valid)
        return OsError.init;
    return closeDescriptor(toDescriptor(handle));
}

PipeReadResult readSome(
    NativeHandle handle,
    u8[] output,
) @system
{
    version (XTB_Checked)
        require(handle.valid, "invalid native pipe handle for read");
    if (output.length == 0)
        return PipeReadResult(OsError.init, 0, PipeReadState.data);

    import core.stdc.errno : EAGAIN, EINTR, EWOULDBLOCK, errno;
    import core.sys.posix.unistd : read;

    for (;;)
    {
        const amount = read(toDescriptor(handle), output.ptr, output.length);
        if (amount > 0)
            return PipeReadResult(
                OsError.init,
                cast(size_t) amount,
                PipeReadState.data,
            );
        if (amount == 0)
            return PipeReadResult(
                OsError.init,
                0,
                PipeReadState.endOfFile,
            );
        if (errno == EINTR)
            continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK)
            return PipeReadResult(
                OsError.init,
                0,
                PipeReadState.wouldBlock,
            );
        return PipeReadResult(lastError(), 0, PipeReadState.data);
    }
}

PipeWriteResult writeSome(
    NativeHandle handle,
    scope const(u8)[] input,
) @system
{
    version (XTB_Checked)
        require(handle.valid, "invalid native pipe handle for write");
    if (input.length == 0)
        return PipeWriteResult(OsError.init, 0, PipeWriteState.data);

    import core.stdc.errno : EAGAIN, EINTR, EPIPE, EWOULDBLOCK, errno;
    import core.sys.posix.signal : SIGPIPE, sigaddset, sigemptyset, sigismember,
        sigpending, sigset_t, sigtimedwait;
    import core.sys.posix.time : timespec;
    import core.sys.posix.unistd : write;

    sigset_t blocked;
    sigset_t previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGPIPE);
    const blockError = signalMask(
        SignalMaskOperation.block,
        &blocked,
        &previous,
    );
    if (blockError.failed)
        return PipeWriteResult(
            blockError,
            0,
            PipeWriteState.data,
        );

    sigset_t pending;
    if (sigpending(&pending) != 0)
    {
        const pendingError = lastError();
        cast(void) signalMask(SignalMaskOperation.setMask, &previous, null);
        return PipeWriteResult(
            pendingError,
            0,
            PipeWriteState.data,
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

    const restoreError = signalMask(
        SignalMaskOperation.setMask,
        &previous,
        null,
    );
    if (restoreError.failed)
        return PipeWriteResult(
            restoreError,
            0,
            PipeWriteState.data,
        );
    if (amount >= 0)
        return PipeWriteResult(
            OsError.init,
            cast(size_t) amount,
            PipeWriteState.data,
        );
    if (writeError == EPIPE)
        return PipeWriteResult(
            OsError.init,
            0,
            PipeWriteState.peerClosed,
        );
    if (writeError == EAGAIN || writeError == EWOULDBLOCK)
        return PipeWriteResult(
            OsError.init,
            0,
            PipeWriteState.wouldBlock,
        );
    return PipeWriteResult(
        fromErrno(writeError),
        0,
        PipeWriteState.data,
    );
}

private NativeHandle fromDescriptor(int descriptor) pure @safe
{
    return fromFileDescriptor(descriptor);
}

private int toDescriptor(NativeHandle handle) pure @safe
{
    return fileDescriptor(handle);
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
