module xtb.os.pipe;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;
import xtb.os.error : OsError, OsErrorKind;
import xtb.os.handle : NativeHandle;
import xtb.os.internal.pipe : NativePipeReadState, NativePipeWriteState;
import xtb.types : u8;

version (linux)
    private import backend = xtb.os.internal.linux.pipe;
else
    private import backend = xtb.os.internal.unsupported.pipe;

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

    private NativeHandle handle_;

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
        return handle_.valid;
    }

    package(xtb) NativeHandle nativeHandle() const pure @safe
    {
        return handle_;
    }
}

struct PipeWriter
{
nothrow @nogc:

    private NativeHandle handle_;

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
        return handle_.valid;
    }

    package(xtb) NativeHandle nativeHandle() const pure @safe
    {
        return handle_;
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

    NativeHandle readerHandle;
    NativeHandle writerHandle;
    const error = backend.createPipeImpl(
        options.readerMode == PipeMode.nonBlocking,
        options.writerMode == PipeMode.nonBlocking,
        &readerHandle,
        &writerHandle,
    );
    if (error.failed)
        return error;

    output.reader.handle_ = readerHandle;
    output.writer.handle_ = writerHandle;
    return OsError.init;
}

OsError close(PipeReader* reader) @system
{
    version (XTB_Checked)
        require(reader !is null, "PipeReader pointer is null");
    return closeOwnedHandle(&reader.handle_);
}

OsError close(PipeWriter* writer) @system
{
    version (XTB_Checked)
        require(writer !is null, "PipeWriter pointer is null");
    return closeOwnedHandle(&writer.handle_);
}

PipeReadResult readSome(PipeReader* reader, u8[] output) @system
{
    version (XTB_Checked)
        require(reader !is null && reader.valid, "invalid PipeReader for read");
    if (output.length == 0)
        return PipeReadResult(OsError.init, 0, PipeReadState.data);

    const result = backend.readSomeImpl(reader.handle_, output);
    return PipeReadResult(
        result.error,
        result.transferred,
        toPublic(result.state),
    );
}

PipeWriteResult writeSome(PipeWriter* writer, scope const(u8)[] input) @system
{
    version (XTB_Checked)
        require(writer !is null && writer.valid, "invalid PipeWriter for write");
    if (input.length == 0)
        return PipeWriteResult(OsError.init, 0, PipeWriteState.data);

    const result = backend.writeSomeImpl(writer.handle_, input);
    return PipeWriteResult(
        result.error,
        result.transferred,
        toPublic(result.state),
    );
}

private bool valid(PipeMode mode) pure @safe
{
    return cast(u8) mode <= cast(u8) PipeMode.nonBlocking;
}

private OsError closeOwnedHandle(NativeHandle* handle) @system
{
    if (!handle.valid)
        return OsError.init;
    const owned = *handle;
    *handle = NativeHandle.init;
    return backend.closeHandleImpl(owned);
}

private PipeReadState toPublic(NativePipeReadState state) pure @safe
{
    final switch (state)
    {
        case NativePipeReadState.data:
            return PipeReadState.data;
        case NativePipeReadState.endOfFile:
            return PipeReadState.endOfFile;
        case NativePipeReadState.wouldBlock:
            return PipeReadState.wouldBlock;
    }
}

private PipeWriteState toPublic(NativePipeWriteState state) pure @safe
{
    final switch (state)
    {
        case NativePipeWriteState.data:
            return PipeWriteState.data;
        case NativePipeWriteState.peerClosed:
            return PipeWriteState.peerClosed;
        case NativePipeWriteState.wouldBlock:
            return PipeWriteState.wouldBlock;
    }
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
