module xtb.fmt.buffered_writer;

nothrow @nogc:

import core.stdc.string;

import xtb.fmt.writer;
import xtb.panic;
import xtb.types;

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
/// `writer()` remains live. The four fields form coupled buffering state:
/// `destination` and `staging` identify the borrowed output path and storage, while
/// `pending` and `failed` track buffered delivery. Do not write directly through
/// the destination while bytes are pending here, because doing so would reorder
/// output.
///
/// A writer returned by `writer()` reports bytes accepted by this buffering layer.
/// Final delivery of staged bytes is checked explicitly through `flush()` / `ok`.
/// `BufferedWriter` never flushes implicitly when it goes out of scope.
struct BufferedWriter
{
nothrow @nogc:

    Writer* destination;
    char[] staging;
    usize pending;
    bool failed;

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
        require(destination !is null, "BufferedWriter destination is null");

        BufferedWriter result;
        result.destination = destination;
        result.staging = staging;
        result.failed = destination is null || !destination.ok;
        return result;
    }

    /// Returns whether this decorator and its destination remain writable.
    bool ok() const pure @safe
    {
        return !this.failed && this.destination !is null && this.destination.ok;
    }

    /// Returns an immediate generic Writer view over this buffering decorator.
    ///
    /// The returned writer borrows this object and must not outlive or move past it.
    Writer writer() return @trusted
    {
        // The callback and context are paired here, and `return` keeps the
        // returned writer from outliving this buffering decorator.
        return Writer.from_sink(&buffered_writer_sink, &this);
    }

    /// Delivers all staged bytes to the underlying writer.
    ///
    /// On a partial downstream failure the accepted prefix is removed from the
    /// staging buffer and the undelivered suffix remains observable via `pending`.
    /// Failure is sticky and later writes are rejected.
    bool flush()
    {
        return this.flush_pending();
    }

    private usize accept(scope const(u8)[] bytes)
    {
        if (bytes.length == 0 || !this.ok) return 0;
        if (this.staging.length == 0) return this.forward(bytes);

        const remaining = this.staging.length - this.pending;
        if (this.pending != 0 && bytes.length > remaining)
        {
            if (!this.flush_pending()) return 0;
        }

        // Once earlier bytes are drained, avoid copying a fragment that is at
        // least as large as the whole staging area.
        if (this.pending == 0 && bytes.length >= this.staging.length)
            return this.forward(bytes);

        cast(void) memcpy(this.staging.ptr + this.pending, bytes.ptr, bytes.length);
        this.pending += bytes.length;
        return bytes.length;
    }

    private usize forward(scope const(u8)[] bytes)
    {
        if (!this.ok || bytes.length == 0) return 0;

        const accepted = this.destination.emit_bytes(bytes);
        if (!this.destination.ok) this.failed = true;
        return accepted;
    }

    private bool flush_pending()
    {
        if (!this.ok)
        {
            this.failed = true;
            return false;
        }
        if (this.pending == 0) return true;

        const delivered = this.destination.emit_bytes(
            cast(const(u8)[]) this.staging[0 .. this.pending],
        );

        if (delivered != 0)
        {
            if (delivered < this.pending)
            {
                cast(void) memmove(
                    this.staging.ptr,
                    this.staging.ptr + delivered,
                    this.pending - delivered,
                );
            }
            this.pending -= delivered;
        }

        if (!this.destination.ok || this.pending != 0) this.failed = true;
        return !this.failed;
    }
}

private usize buffered_writer_sink(void* context, scope const(u8)[] bytes) @system
{
    auto buffered = cast(BufferedWriter*) context;
    if (buffered is null) return 0;
    return buffered.accept(bytes);
}

version (unittest)
{
    private struct BufferedWriterTestSinkState
    {
        char[256] storage;
        usize length;
        usize max_per_call = usize.max;
        usize successful_call_limit = usize.max;
        usize calls;
        const(u8)* first_pointer;
        usize first_length;
        bool reject;
    }

    private usize buffered_writer_test_destination_sink(
        void* context,
        scope const(u8)[] bytes,
    ) @system
    {
        // Tests pass a live BufferedWriterTestSinkState as the opaque sink context.
        auto state = cast(BufferedWriterTestSinkState*) context;
        if (
            state is null
            || state.reject
            || bytes.length == 0
            || state.calls >= state.successful_call_limit
        )
        {
            return 0;
        }

        if (state.calls == 0)
        {
            state.first_pointer = bytes.ptr;
            state.first_length = bytes.length;
        }

        auto amount = bytes.length < state.max_per_call
            ? bytes.length
            : state.max_per_call;
        const available = state.storage.length - state.length;
        if (amount > available) amount = available;
        if (amount == 0) return 0;

        cast(void) memcpy(state.storage.ptr + state.length, bytes.ptr, amount);
        state.length += amount;
        ++state.calls;
        return amount;
    }
}

unittest
{
    static assert(!__traits(compiles, () @system
    {
        BufferedWriterTestSinkState state;
        auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
        char[8] storage;
        auto first = BufferedWriter.create(&destination, storage[]);
        auto second = first;
    }));

    static assert(!__traits(compiles, () @system
    {
        BufferedWriterTestSinkState state;
        auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
        char[8] first_storage;
        char[8] second_storage;
        auto first = BufferedWriter.create(&destination, first_storage[]);
        auto second = BufferedWriter.create(&destination, second_storage[]);
        second = first;
    }));
}

unittest
{
    BufferedWriterTestSinkState state;
    auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
    char[8] staging;
    auto buffered = BufferedWriter.create(&destination, staging[]);
    auto output = buffered.writer();

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
    auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
    char[4] staging;
    auto buffered = BufferedWriter.create(&destination, staging[]);
    auto output = buffered.writer();

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
    auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
    char[4] staging;
    auto buffered = BufferedWriter.create(&destination, staging[]);
    auto output = buffered.writer();
    String large = "0123456789";

    output.put(large);
    assert(output.ok);
    assert(buffered.pending == 0);
    assert(destination.written == large.length);
    assert(state.calls == 1);
    assert(state.first_pointer == cast(const(u8)*) large.ptr);
    assert(state.first_length == large.length);
    assert(state.storage[0 .. state.length] == large);
}

unittest
{
    BufferedWriterTestSinkState state;
    auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
    char[4] staging;
    auto buffered = BufferedWriter.create(&destination, staging[]);
    auto output = buffered.writer();
    String exact_capacity = "abcd";

    output.put(exact_capacity);
    assert(output.ok);
    assert(buffered.pending == 0);
    assert(destination.written == exact_capacity.length);
    assert(state.calls == 1);
    assert(state.first_pointer == cast(const(u8)*) exact_capacity.ptr);
    assert(state.first_length == exact_capacity.length);
    assert(state.storage[0 .. state.length] == exact_capacity);
}

unittest
{
    BufferedWriterTestSinkState state;
    auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
    char[4] staging;
    auto buffered = BufferedWriter.create(&destination, staging[]);
    auto output = buffered.writer();

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
    state.max_per_call = 2;
    auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
    char[8] staging;
    auto buffered = BufferedWriter.create(&destination, staging[]);
    auto output = buffered.writer();

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
    state.max_per_call = 2;
    state.successful_call_limit = 1;
    auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
    char[8] staging;
    auto buffered = BufferedWriter.create(&destination, staging[]);
    auto output = buffered.writer();

    output.put("abcd");
    assert(output.ok);
    assert(buffered.pending == 4);

    assert(!buffered.flush());
    assert(!buffered.ok);
    assert(destination.written == 2);
    assert(buffered.pending == 2);
    assert(staging[0 .. 2] == "cd");
    assert(state.storage[0 .. state.length] == "ab");

    const accepted_before = output.written;
    output.put("ignored");
    assert(!output.ok);
    assert(output.written == accepted_before);
    assert(buffered.pending == 2);
}

unittest
{
    BufferedWriterTestSinkState state;
    auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
    char[] no_staging;
    auto buffered = BufferedWriter.create(&destination, no_staging);
    auto output = buffered.writer();

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
    auto destination = Writer.from_sink(&buffered_writer_test_destination_sink, &state);
    char[8] staging;

    {
        auto buffered = BufferedWriter.create(&destination, staging[]);
        auto output = buffered.writer();
        output.put("pending");
        assert(buffered.pending == 7);
    }

    // BufferedWriter has no destructor-side flush. Buffering policy remains
    // explicit and cannot unexpectedly perform output during scope teardown.
    assert(state.calls == 0);
    assert(destination.written == 0);
}
