module xtb.core.fmt.buffered_writer;

nothrow @nogc:

import xtb.core.fmt.writer : Writer;
import xtb.core.types : String, u8;

version (XTB_Checked) import xtb.core.panic : require;

/// Explicit caller-buffered decorator over an immediate `Writer`.
///
/// Small fragments are copied into caller-owned staging storage and emitted to
/// the destination when that storage must be drained or `flush` is called. Once
/// pending bytes are drained, a fragment at least as large as the staging capacity
/// bypasses staging and is forwarded directly without an intermediate copy.
/// Zero-length staging therefore acts as a direct pass-through.
///
/// The decorator borrows both the destination writer and staging storage. Neither
/// may be moved, destroyed, or reused while this object or a writer returned by
/// `writer()` remains live. Do not write directly through the destination while
/// bytes are pending here, because doing so would reorder output.
///
/// A writer returned by `writer()` reports bytes accepted by this buffering layer.
/// Final delivery of staged bytes is checked explicitly through `flush()` / `ok`.
/// `BufferedWriter` never flushes implicitly when it goes out of scope.
struct BufferedWriter
{
nothrow @nogc:

    private Writer* destination_;
    private char[] staging_;
    private size_t staged_;
    private bool failed_;

    @disable this(this);
    @disable ref BufferedWriter opAssign(BufferedWriter source) return;

    /// Creates a buffering decorator over `destination` using caller-owned storage.
    ///
    /// `destination` must be non-null and outlive the returned decorator.
    static BufferedWriter create(
        return scope Writer* destination,
        return scope char[] staging,
    ) @safe
    {
        version (XTB_Checked)
            require(destination !is null, "BufferedWriter destination is null");

        BufferedWriter result;
        result.destination_ = destination;
        result.staging_ = staging;
        result.failed_ = destination is null || !destination.ok;
        return result;
    }

    /// Returns whether this decorator and its destination remain writable.
    bool ok() const pure @safe
    {
        return !failed_ && destination_ !is null && destination_.ok;
    }

    /// Number of accepted bytes still staged locally.
    size_t pending() const pure @safe
    {
        return staged_;
    }

    /// Returns an immediate generic Writer view over this buffering decorator.
    ///
    /// The returned writer borrows this object and must not outlive or move past it.
    Writer writer() return @trusted
    {
        return Writer.fromSink(&bufferedWriterSink, &this);
    }

    /// Delivers all staged bytes to the underlying writer.
    ///
    /// On a partial downstream failure the accepted prefix is removed from the
    /// staging buffer and the undelivered suffix remains observable via `pending`.
    /// Failure is sticky and later writes are rejected.
    bool flush()
    {
        return flushPending();
    }

    private size_t accept(scope const(u8)[] bytes)
    {
        if (bytes.length == 0 || !ok)
            return 0;

        if (staging_.length == 0)
            return forward(bytes);

        const remaining = staging_.length - staged_;
        if (staged_ != 0 && bytes.length > remaining)
        {
            if (!flushPending())
                return 0;
        }

        // Once earlier bytes are drained, avoid copying a fragment that is at
        // least as large as the whole staging area.
        if (staged_ == 0 && bytes.length >= staging_.length)
            return forward(bytes);

        import core.stdc.string : memcpy;

        memcpy(staging_.ptr + staged_, bytes.ptr, bytes.length);
        staged_ += bytes.length;
        return bytes.length;
    }

    private size_t forward(scope const(u8)[] bytes)
    {
        if (!ok || bytes.length == 0)
            return 0;

        const accepted = destination_.emitBytes(bytes);
        if (!destination_.ok)
            failed_ = true;
        return accepted;
    }

    private bool flushPending()
    {
        if (!ok)
        {
            failed_ = true;
            return false;
        }
        if (staged_ == 0)
            return true;

        const delivered = destination_.emitBytes(
            cast(const(u8)[]) staging_[0 .. staged_],
        );

        if (delivered != 0)
        {
            if (delivered < staged_)
            {
                import core.stdc.string : memmove;

                memmove(staging_.ptr, staging_.ptr + delivered, staged_ - delivered);
            }
            staged_ -= delivered;
        }

        if (!destination_.ok || staged_ != 0)
            failed_ = true;
        return !failed_;
    }
}

private size_t bufferedWriterSink(
    void* context,
    scope const(u8)[] bytes,
)
@trusted
{
    BufferedWriter* buffered = cast(BufferedWriter*) context;
    if (buffered is null)
        return 0;
    return buffered.accept(bytes);
}

version (unittest) private struct BufferedWriterTestSinkState
{
    char[256] storage;
    size_t length;
    size_t maxPerCall = size_t.max;
    size_t successfulCallLimit = size_t.max;
    size_t calls;
    const(u8)* firstPointer;
    size_t firstLength;
    bool reject;
}

version (unittest) private size_t bufferedWriterTestDestinationSink(
    void* context,
    scope const(u8)[] bytes,
)
@trusted
{
    import core.stdc.string : memcpy;

    BufferedWriterTestSinkState* state = cast(BufferedWriterTestSinkState*) context;
    if (state is null || state.reject || bytes.length == 0 ||
        state.calls >= state.successfulCallLimit)
        return 0;

    if (state.calls == 0)
    {
        state.firstPointer = bytes.ptr;
        state.firstLength = bytes.length;
    }

    size_t amount = bytes.length < state.maxPerCall
        ? bytes.length : state.maxPerCall;
    const available = state.storage.length - state.length;
    if (amount > available)
        amount = available;
    if (amount == 0)
        return 0;

    memcpy(state.storage.ptr + state.length, bytes.ptr, amount);
    state.length += amount;
    ++state.calls;
    return amount;
}

unittest
{
    static assert(!__traits(compiles, {
            BufferedWriterTestSinkState state;
            Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
            char[8] storage;
            BufferedWriter first = BufferedWriter.create(&destination, storage[]);
            BufferedWriter second = first;
        }));

    static assert(!__traits(compiles, {
            BufferedWriterTestSinkState state;
            Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
            char[8] firstStorage;
            char[8] secondStorage;
            BufferedWriter first = BufferedWriter.create(&destination, firstStorage[]);
            BufferedWriter second = BufferedWriter.create(&destination, secondStorage[]);
            second = first;
        }));

    BufferedWriterTestSinkState state;
    Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
    char[8] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();

    output.write("ab", "cd", "ef");
    assert(output.ok);
    assert(output.written == 6);
    assert(buffered.ok);
    assert(buffered.pending == 6);
    assert(destination.written == 0);
    assert(state.calls == 0);

    assert(buffered.flush());
    assert(buffered.pending == 0);
    assert(destination.written == 6);
    assert(state.calls == 1);
    assert(state.storage[0 .. state.length] == "abcdef");
}

unittest
{
    BufferedWriterTestSinkState state;
    Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
    char[4] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();

    output.write("ab", "cd", "ef");
    assert(output.ok);
    assert(state.calls == 1);
    assert(state.storage[0 .. state.length] == "abcd");
    assert(buffered.pending == 2);

    assert(buffered.flush());
    assert(state.calls == 2);
    assert(state.storage[0 .. state.length] == "abcdef");
}

unittest
{
    BufferedWriterTestSinkState state;
    Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
    char[4] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();
    String large = "0123456789";

    output.put(large);
    assert(output.ok);
    assert(buffered.pending == 0);
    assert(destination.written == large.length);
    assert(state.calls == 1);
    assert(state.firstPointer == cast(const(u8)*) large.ptr);
    assert(state.firstLength == large.length);
    assert(state.storage[0 .. state.length] == large);
}

unittest
{
    BufferedWriterTestSinkState state;
    Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
    char[4] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();
    String exactCapacity = "abcd";

    output.put(exactCapacity);
    assert(output.ok);
    assert(buffered.pending == 0);
    assert(destination.written == exactCapacity.length);
    assert(state.calls == 1);
    assert(state.firstPointer == cast(const(u8)*) exactCapacity.ptr);
    assert(state.firstLength == exactCapacity.length);
    assert(state.storage[0 .. state.length] == exactCapacity);
}

unittest
{
    BufferedWriterTestSinkState state;
    Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
    char[4] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();

    output.put("ab");
    output.put("0123456789");
    assert(output.ok);
    assert(buffered.pending == 0);
    assert(state.calls == 2);
    assert(state.storage[0 .. state.length] == "ab0123456789");
}

unittest
{
    BufferedWriterTestSinkState state;
    state.maxPerCall = 2;
    Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
    char[8] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();

    output.put("abcdef");
    assert(state.calls == 0);
    assert(buffered.flush());
    assert(state.calls == 3);
    assert(destination.written == 6);
    assert(state.storage[0 .. state.length] == "abcdef");
}

unittest
{
    BufferedWriterTestSinkState state;
    state.maxPerCall = 2;
    state.successfulCallLimit = 1;
    Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
    char[8] staging;
    BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
    Writer output = buffered.writer();

    output.put("abcd");
    assert(output.ok);
    assert(buffered.pending == 4);

    assert(!buffered.flush());
    assert(!buffered.ok);
    assert(destination.written == 2);
    assert(buffered.pending == 2);
    assert(staging[0 .. 2] == "cd");
    assert(state.storage[0 .. state.length] == "ab");

    const acceptedBefore = output.written;
    output.put("ignored");
    assert(!output.ok);
    assert(output.written == acceptedBefore);
    assert(buffered.pending == 2);
}

unittest
{
    BufferedWriterTestSinkState state;
    Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
    char[] noStaging;
    BufferedWriter buffered = BufferedWriter.create(&destination, noStaging);
    Writer output = buffered.writer();

    output.put("direct");
    assert(output.ok);
    assert(buffered.pending == 0);
    assert(state.calls == 1);
    assert(state.storage[0 .. state.length] == "direct");
    assert(buffered.flush());
}

unittest
{
    BufferedWriterTestSinkState state;
    Writer destination = Writer.fromSink(&bufferedWriterTestDestinationSink, &state);
    char[8] staging;

    {
        BufferedWriter buffered = BufferedWriter.create(&destination, staging[]);
        Writer output = buffered.writer();
        output.put("pending");
        assert(buffered.pending == 7);
    }

    // BufferedWriter has no destructor-side flush. Buffering policy remains
    // explicit and cannot unexpectedly perform output during scope teardown.
    assert(state.calls == 0);
    assert(destination.written == 0);
}
