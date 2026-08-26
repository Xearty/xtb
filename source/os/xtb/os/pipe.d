module xtb.os.pipe;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.types : u8;
import xtb.os.error : OsError, OsErrorKind, lastError, unsupported;

version (linux) import xtb.os.error : fromErrno;

enum PipeMode : ubyte
{
    blocking,
    nonBlocking,
}

struct PipeOptions
{
    PipeMode readerMode;
    PipeMode writerMode;
}

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

struct PipeReader
{
nothrow @nogc:

    private int descriptor_ = -1;

    @disable this(this);
    @disable ref PipeReader opAssign(PipeReader source) return;

    /// Explicitly ends this pipe endpoint's owning lifetime.
    ///
    /// Close errors are discarded; call `close` directly when they matter.
    void deinit() @system
    {
        cast(void) close(&this);
    }

    bool valid() const pure @safe
    {
        return descriptor_ >= 0;
    }

    package(xtb) int nativeDescriptor() const pure @safe
    {
        return descriptor_;
    }
}

struct PipeWriter
{
nothrow @nogc:

    private int descriptor_ = -1;

    @disable this(this);
    @disable ref PipeWriter opAssign(PipeWriter source) return;

    /// Explicitly ends this pipe endpoint's owning lifetime.
    ///
    /// Close errors are discarded; call `close` directly when they matter.
    void deinit() @system
    {
        cast(void) close(&this);
    }

    bool valid() const pure @safe
    {
        return descriptor_ >= 0;
    }

    package(xtb) int nativeDescriptor() const pure @safe
    {
        return descriptor_;
    }
}

struct Pipe
{
nothrow @nogc:

    PipeReader reader;
    PipeWriter writer;

    @disable this(this);
    @disable ref Pipe opAssign(Pipe source) return;

    bool valid() const pure @safe
    {
        return reader.valid && writer.valid;
    }

    void deinit()
    {
        reader.deinit();
        writer.deinit();
    }
}

OsError createPipe(PipeOptions options, Pipe* output) @system
{
    version (XTB_Checked)
    {
        require(output !is null, "Pipe output pointer is null");
        require(!output.reader.valid && !output.writer.valid,
            "Pipe output must be empty");
    }
    if (!valid(options.readerMode) || !valid(options.writerMode))
        return OsError(OsErrorKind.invalidArgument, 0);

    version (linux)
    {
        import core.sys.posix.fcntl : O_CLOEXEC;

        int[2] descriptors = [-1, -1];
        if (nativePipe2(descriptors.ptr, O_CLOEXEC) != 0)
            return lastError();

        OsError error;
        if (options.readerMode == PipeMode.nonBlocking)
            error = setNonBlocking(descriptors[0]);
        if (error.succeeded && options.writerMode == PipeMode.nonBlocking)
            error = setNonBlocking(descriptors[1]);
        if (error.failed)
        {
            closeDescriptor(descriptors[0]);
            closeDescriptor(descriptors[1]);
            return error;
        }

        output.reader.descriptor_ = descriptors[0];
        output.writer.descriptor_ = descriptors[1];
        return OsError.init;
    }
    else
        return unsupported();
}

OsError close(PipeReader* reader) @system
{
    version (XTB_Checked)
        require(reader !is null, "PipeReader pointer is null");
    return closeOwnedDescriptor(&reader.descriptor_);
}

OsError close(PipeWriter* writer) @system
{
    version (XTB_Checked)
        require(writer !is null, "PipeWriter pointer is null");
    return closeOwnedDescriptor(&writer.descriptor_);
}

PipeReadResult readSome(PipeReader* reader, u8[] output) @system
{
    version (XTB_Checked)
        require(reader !is null && reader.valid, "invalid PipeReader for read");
    if (output.length == 0)
        return PipeReadResult(OsError.init, 0, PipeReadState.data);

    version (linux)
    {
        import core.stdc.errno : EAGAIN, EINTR, EWOULDBLOCK, errno;
        import core.sys.posix.unistd : read;

        for (;;)
        {
            const amount = read(reader.descriptor_, output.ptr, output.length);
            if (amount > 0)
                return PipeReadResult(
                    OsError.init,
                    cast(size_t) amount,
                    PipeReadState.data,
                );
            if (amount == 0)
                return PipeReadResult(OsError.init, 0, PipeReadState.endOfFile);
            if (errno == EINTR)
                continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                return PipeReadResult(OsError.init, 0, PipeReadState.wouldBlock);
            return PipeReadResult(lastError(), 0, PipeReadState.data);
        }
    }
    else
        return PipeReadResult(unsupported(), 0, PipeReadState.data);
}

PipeWriteResult writeSome(PipeWriter* writer, scope const(u8)[] input) @system
{
    version (XTB_Checked)
        require(writer !is null && writer.valid, "invalid PipeWriter for write");
    if (input.length == 0)
        return PipeWriteResult(OsError.init, 0, PipeWriteState.data);

    version (linux)
        return writeWithoutSigpipe(writer.descriptor_, input);
    else
        return PipeWriteResult(unsupported(), 0, PipeWriteState.data);
}

private bool valid(PipeMode mode) pure @safe
{
    return cast(u8) mode <= cast(u8) PipeMode.nonBlocking;
}

private OsError closeOwnedDescriptor(int* descriptor) @system
{
    if (*descriptor < 0)
        return OsError.init;
    version (linux)
    {
        const owned = *descriptor;
        *descriptor = -1;
        return closeDescriptor(owned);
    }
    else
    {
        *descriptor = -1;
        return unsupported();
    }
}

version (linux) private extern (C) pragma(mangle, "pipe2")
int nativePipe2(int* descriptors, int flags);

version (linux) private OsError closeDescriptor(int descriptor) @system
{
    import core.sys.posix.unistd : nativeClose = close;

    return nativeClose(descriptor) == 0 ? OsError.init : lastError();
}

version (linux) private OsError setNonBlocking(int descriptor) @system
{
    import core.sys.posix.fcntl : F_GETFL, F_SETFL, O_NONBLOCK, fcntl;

    const flags = fcntl(descriptor, F_GETFL, 0);
    if (flags < 0)
        return lastError();
    return fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
        ? OsError.init : lastError();
}

version (linux) private PipeWriteResult writeWithoutSigpipe(
    int descriptor,
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
        return PipeWriteResult(fromErrno(code), 0, PipeWriteState.data);

    sigset_t pending;
    if (sigpending(&pending) != 0)
    {
        const pendingError = lastError();
        pthread_sigmask(SIG_SETMASK, &previous, null);
        return PipeWriteResult(pendingError, 0, PipeWriteState.data);
    }
    const wasPending = sigismember(&pending, SIGPIPE) == 1;

    long amount;
    do
        amount = write(descriptor, input.ptr, input.length);
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
        return PipeWriteResult(fromErrno(code), 0, PipeWriteState.data);
    if (amount >= 0)
        return PipeWriteResult(OsError.init, cast(size_t) amount,
            PipeWriteState.data);
    if (writeError == EPIPE)
        return PipeWriteResult(OsError.init, 0, PipeWriteState.peerClosed);
    if (writeError == EAGAIN || writeError == EWOULDBLOCK)
        return PipeWriteResult(OsError.init, 0, PipeWriteState.wouldBlock);
    return PipeWriteResult(fromErrno(writeError), 0, PipeWriteState.data);
}

unittest
{
    version (linux)
    {
        Pipe pipe;
        assert(createPipe(PipeOptions.init, &pipe).succeeded);
        assert(pipe.valid);

        u8[4] bytes = [1, 2, 3, 4];
        const written = (&pipe.writer).writeSome(bytes[]);
        assert(written.error.succeeded);
        assert(written.state == PipeWriteState.data && written.transferred == 4);

        u8[4] received;
        const read = (&pipe.reader).readSome(received[]);
        assert(read.error.succeeded);
        assert(read.state == PipeReadState.data && read.transferred == 4);
        assert(received == bytes);

        assert((&pipe.writer).writeSome(null).transferred == 0);
        assert((&pipe.reader).readSome(null).transferred == 0);
        assert(close(&pipe.writer).succeeded);
        assert((&pipe.reader).readSome(received[]).state ==
                PipeReadState.endOfFile);
        assert(close(&pipe.reader).succeeded);
        assert(close(&pipe.reader).succeeded);

        PipeOptions nonBlockingOptions;
        nonBlockingOptions.readerMode = PipeMode.nonBlocking;
        Pipe nonBlocking;
        assert(createPipe(nonBlockingOptions, &nonBlocking).succeeded);
        assert((&nonBlocking.reader).readSome(received[]).state ==
                PipeReadState.wouldBlock);
        assert(close(&nonBlocking.reader).succeeded);
        assert((&nonBlocking.writer).writeSome(bytes[]).state ==
                PipeWriteState.peerClosed);
        nonBlocking.deinit();

        PipeOptions invalid;
        invalid.readerMode = cast(PipeMode) 2;
        Pipe rejected;
        assert(createPipe(invalid, &rejected).kind ==
                OsErrorKind.invalidArgument);
    }
}
