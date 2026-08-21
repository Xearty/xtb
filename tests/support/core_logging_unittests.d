module xtb.core.logging.tests;

nothrow @nogc:

import core.stdc.stdio : FILE;
import xtb.core.ansi : AnsiColor, AnsiStyle, ansiResetSequence, ansiSequence;
import xtb.core.logging;
import xtb.core.logging.sgr : SgrParseKind, maxSupportedSgrLength, parseSgrPrefix, safeSgrPrefixLength;
import xtb.core.logging.file : fileFlush;
import xtb.core.logging.sink : submit;
import xtb.core.logging.writer : createLogMessageWriter;
import xtb.core.string;

version (unittest)
{
    import xtb.core.pretty_print : PrettyPrintLayout, PrettyPrintOptions, pretty;
    import xtb.core.print : Writer, writeBuffer;

    private struct CapturedEvent
    {
    nothrow @nogc:

        LogSinkEventKind kind;
        char[64] bytes;
        size_t length;
        AnsiStyle style;
        const(char)* source;

        String text() const return @trusted
        {
            return bytes[0 .. length];
        }
    }

    private struct Capture
    {
    nothrow @nogc:

        CapturedEvent[128] events;
        size_t count;
        size_t flushCount;
        bool flushAccepted;
        size_t rejectAt = size_t.max;

        void clear()
        {
            count = 0;
            rejectAt = size_t.max;
        }
    }

    private bool captureSink(void* context, scope const LogSinkEvent* event)
    {
        Capture* capture = cast(Capture*) context;
        if (event is null || capture.count >= capture.events.length)
            return false;

        const eventIndex = capture.count;
        CapturedEvent* destination = &capture.events[capture.count++];
        destination.kind = event.kind;
        destination.style = event.style;
        destination.source = event.bytes.ptr;
        destination.length = event.bytes.length < destination.bytes.length
            ? event.bytes.length
            : destination.bytes.length;
        foreach (index; 0 .. destination.length)
            destination.bytes[index] = event.bytes[index];
        if (destination.length != event.bytes.length)
            return false;
        return eventIndex != capture.rejectAt;
    }

    private bool captureFlush(void* context)
    {
        Capture* capture = cast(Capture*) context;
        ++capture.flushCount;
        return capture.flushAccepted;
    }

    private struct ChunkCounter
    {
        size_t calls;
        size_t bytes;
        const(char)* source;
        size_t rejectAt = size_t.max;
    }

    private struct MessageCapture
    {
    nothrow @nogc:

        char[8192] bytes;
        size_t length;
        size_t chunks;
        size_t maxChunk;

        String text() const return @trusted
        {
            return bytes[0 .. length];
        }
    }

    private bool chunkCounterSink(
        void* context,
        scope const LogSinkEvent* event,
    )
    {
        ChunkCounter* counter = cast(ChunkCounter*) context;
        if (counter is null || event is null)
            return false;
        if (event.kind != LogSinkEventKind.messageChunk)
            return true;

        const index = counter.calls++;
        counter.bytes += event.bytes.length;
        counter.source = event.bytes.ptr;
        return index != counter.rejectAt;
    }

    private bool messageCaptureSink(
        void* context,
        scope const LogSinkEvent* event,
    )
    {
        MessageCapture* capture = cast(MessageCapture*) context;
        if (capture is null || event is null)
            return false;
        if (event.kind != LogSinkEventKind.messageChunk)
            return true;
        if (event.bytes.length > capture.bytes.length - capture.length)
            return false;

        foreach (index; 0 .. event.bytes.length)
            capture.bytes[capture.length + index] = event.bytes[index];
        capture.length += event.bytes.length;
        ++capture.chunks;
        if (event.bytes.length > capture.maxChunk)
            capture.maxChunk = event.bytes.length;
        return true;
    }

    private bool rejectFlush(void*)
    {
        return false;
    }

    private size_t readFileContents(FILE* file, char[] destination) @system
    {
        import core.stdc.stdio : fread, rewind;

        rewind(file);
        return fread(destination.ptr, 1, destination.length, file);
    }

    private struct PrefixProbe
    {
        size_t calls;
        bool accepted = true;
        AnsiStyle style;
    }

    private struct StreamProducerProbe
    {
        size_t* calls;

        @disable this(this);

        void opCall(scope ref LogMessageWriter writer) nothrow @nogc
        {
            ++*calls;
            writer.write("non-copyable producer");
        }
    }

    private struct StreamFormatProbe
    {
        int value;

        void formatTo(ref Writer writer) nothrow @nogc
        {
            writer.put("probe(");
            writer.value(value);
            writer.put(')');
        }
    }

    private struct PrettyStreamProbe
    {
        String payload;

        void prettyFormatTo(
            ref Writer writer,
            scope const ref PrettyPrintOptions,
        ) const nothrow @nogc
        {
            writer.put(payload);
        }
    }

    private bool prefixProbe(void* context, LogPrefixWriter* output)
    {
        PrefixProbe* probe = cast(PrefixProbe*) context;
        if (probe is null || output is null)
            return false;
        ++probe.calls;
        if (!output.write("prefix", probe.style))
            return false;
        if (!output.write(" "))
            return false;
        return probe.accepted;
    }

    private struct RecursiveCapture
    {
    nothrow @nogc:

        Logger* logger;
        LogStatus nestedStatus;
        Capture events;
        bool nestedAttempted;
    }

    private struct SinkSwapCapture
    {
    nothrow @nogc:

        Logger* logger;
        Capture* current;
        LogSinkRef replacement;
        bool swapped;
    }

    private bool swappingSink(void* context, scope const LogSinkEvent* event)
    {
        SinkSwapCapture* capture = cast(SinkSwapCapture*) context;
        if (!capture.swapped && event.kind == LogSinkEventKind.beginRecord)
        {
            capture.swapped = true;
            (*capture.logger).setSink(capture.replacement);
        }
        return captureSink(capture.current, event);
    }

    private bool recursiveSink(void* context, scope const LogSinkEvent* event)
    {
        RecursiveCapture* capture = cast(RecursiveCapture*) context;
        if (!capture.nestedAttempted && event.kind == LogSinkEventKind.messageChunk)
        {
            capture.nestedAttempted = true;
            capture.nestedStatus = (*capture.logger).log(LogLevel.error, "nested").status;
        }
        return captureSink(&capture.events, event);
    }

    private void assertEvent(
        scope const ref Capture capture,
        size_t index,
        LogSinkEventKind kind,
        scope String text = null,
    )
    {
        assert(index < capture.count);
        assert(capture.events[index].kind == kind);
        assert(capture.events[index].text.equal(text));
    }

    private void assertSameEvents(
        scope const ref Capture left,
        scope const ref Capture right,
    )
    {
        assert(left.count == right.count);
        foreach (index; 0 .. left.count)
        {
            assert(left.events[index].kind == right.events[index].kind);
            assert(left.events[index].text.equal(right.events[index].text));
            assert(left.events[index].style == right.events[index].style);
        }
    }

    private void assertSuccessfulRecord(
        scope const ref Capture capture,
        scope String label,
        scope String message,
        AnsiStyle labelStyle,
        AnsiStyle messageStyle,
    )
    {
        const expectedCount = message.length == 0 ? 7 : 8;
        assert(capture.count == expectedCount);
        assertEvent(capture, 0, LogSinkEventKind.beginRecord);
        assertEvent(capture, 1, LogSinkEventKind.text, label);
        assert(capture.events[1].style == labelStyle);
        assertEvent(capture, 2, LogSinkEventKind.text, " ");
        assert(!capture.events[2].style.enabled);
        assertEvent(capture, 3, LogSinkEventKind.beginMessage);
        assert(capture.events[3].style == messageStyle);
        size_t next = 4;
        if (message.length != 0)
        {
            assertEvent(capture, next, LogSinkEventKind.messageChunk, message);
            assert(capture.events[next].style == messageStyle);
            ++next;
        }
        assertEvent(capture, next++, LogSinkEventKind.endMessage);
        assertEvent(capture, next++, LogSinkEventKind.text, "\n");
        assertEvent(capture, next, LogSinkEventKind.endRecord);
    }

    private struct OrderedEvent
    {
        ubyte branch;
        LogSinkEventKind kind;
    }

    private struct OrderedCapture
    {
        OrderedEvent[64] events;
        size_t count;
    }

    private struct OrderedBranch
    {
        OrderedCapture* order;
        Capture* capture;
        ubyte branch;
    }

    private bool orderedSink(void* context, scope const LogSinkEvent* event)
    {
        OrderedBranch* branch = cast(OrderedBranch*) context;
        if (branch is null || branch.order is null || event is null ||
            branch.order.count >= branch.order.events.length)
            return false;
        branch.order.events[branch.order.count++] = OrderedEvent(
            branch.branch,
            event.kind,
        );
        return captureSink(branch.capture, event);
    }

    private bool orderedFlush(void* context)
    {
        OrderedBranch* branch = cast(OrderedBranch*) context;
        return branch !is null && branch.capture !is null &&
            captureFlush(branch.capture);
    }

    private struct FormatOnceProbe
    {
    nothrow @nogc:

        size_t* calls;

        void formatTo(ref Writer writer) const @trusted
        {
            ++*cast(size_t*) calls;
            writer.put("formatted-once");
        }
    }

    private struct ForwardingFailure
    {
        LogSinkRef child;
        LogSinkEventKind rejectKind;
        bool rejected;
    }

    private bool forwardingFailureSink(void* context, scope const LogSinkEvent* event)
    {
        ForwardingFailure* failure = cast(ForwardingFailure*) context;
        if (failure is null || event is null)
            return false;
        const childAccepted = failure.child.submit(event);
        if (!failure.rejected && event.kind == failure.rejectKind)
        {
            failure.rejected = true;
            return false;
        }
        return childAccepted;
    }

    version (Posix)
    {
        import core.sys.posix.sys.types : pthread_barrier_t;

        private struct ConcurrentLogContext
        {
            FILE* file;
            char marker;
            size_t iterations;
            pthread_barrier_t* barrier;
            bool succeeded;
        }

        private extern (C) void* concurrentLogWorker(void* context)
        {
            import core.sys.posix.pthread : pthread_barrier_wait;

            ConcurrentLogContext* worker = cast(ConcurrentLogContext*) context;
            char[64] message;
            foreach (ref value; message)
                value = worker.marker;
            char[128] storage;
            Logger logger = Logger.create(
                plainFileLogSink(worker.file),
                storage[],
                LogLevel.info,
            );
            pthread_barrier_wait(worker.barrier);
            foreach (_; 0 .. worker.iterations)
            {
                if (!logger.info(message[]).delivered)
                    return null;
            }
            worker.succeeded = true;
            return null;
        }

        private struct FileTryLockContext
        {
            FILE* file;
            bool acquired;
        }

        private extern (C) void* fileTryLockWorker(void* context)
        {
            import core.sys.posix.stdio : ftrylockfile, funlockfile;

            FileTryLockContext* worker = cast(FileTryLockContext*) context;
            if (ftrylockfile(worker.file) == 0)
            {
                worker.acquired = true;
                funlockfile(worker.file);
            }
            return null;
        }
    }
}

static assert(__traits(isCopyable, LogSinkRef));
static assert(__traits(isCopyable, LogSinkEvent));
static assert(__traits(isCopyable, LogPrefixRef));
static assert(!__traits(isCopyable, PrefixLogSink));
static assert(!__traits(isCopyable, TeeLogSink));
static assert(!__traits(isCopyable, Logger));

unittest
{
    const prefixStyle = AnsiStyle.foreground(AnsiColor.brightBlack).dim;
    PrefixProbe probe;
    probe.style = prefixStyle;
    Capture capture;
    capture.flushAccepted = true;
    PrefixLogSink prefixed = PrefixLogSink.create(
        LogSinkRef.create(&captureSink, &capture, &captureFlush),
        LogPrefixRef.create(&prefixProbe, &probe),
    );
    assert(prefixed.valid);
    char[128] storage;
    Logger logger = Logger.create(prefixed.sinkRef(), storage[], LogLevel.trace);

    const delivered = logger.info("hello");
    assert(delivered.status == LogStatus.delivered);
    assert(probe.calls == 1);
    assert(capture.count == 10);
    assertEvent(capture, 0, LogSinkEventKind.beginRecord);
    assertEvent(capture, 1, LogSinkEventKind.text, "prefix");
    assert(capture.events[1].style == prefixStyle);
    assertEvent(capture, 2, LogSinkEventKind.text, " ");
    assertEvent(capture, 3, LogSinkEventKind.text, "[info]");
    assertEvent(capture, 4, LogSinkEventKind.text, " ");
    assertEvent(capture, 5, LogSinkEventKind.beginMessage);
    assertEvent(capture, 6, LogSinkEventKind.messageChunk, "hello");
    assertEvent(capture, 7, LogSinkEventKind.endMessage);
    assertEvent(capture, 8, LogSinkEventKind.text, "\n");
    assertEvent(capture, 9, LogSinkEventKind.endRecord);
    assert(logger.flush());
    assert(capture.flushCount == 1);

    capture.clear();
    probe.accepted = false;
    const providerFailed = logger.warning("still delivered");
    assert(providerFailed.status == LogStatus.sinkFailed);
    assert(capture.count == 10);
    assertEvent(capture, 9, LogSinkEventKind.endRecord);

    capture.clear();
    probe.accepted = true;
    capture.rejectAt = 1;
    const prefixWriteFailed = logger.error("body survives");
    assert(prefixWriteFailed.status == LogStatus.sinkFailed);
    assert(capture.count == 9);
    assertEvent(capture, 2, LogSinkEventKind.text, "[error]");
    assertEvent(capture, 8, LogSinkEventKind.endRecord);

    capture.clear();
    capture.rejectAt = 0;
    const callsBefore = probe.calls;
    const beginFailed = logger.info("not begun");
    assert(beginFailed.status == LogStatus.sinkFailed);
    assert(probe.calls == callsBefore);
    assert(capture.count == 1);
    assertEvent(capture, 0, LogSinkEventKind.beginRecord);

    capture.clear();
    const recovered = logger.info("next record");
    assert(recovered.status == LogStatus.delivered);
    assert(capture.count == 10);
    assertEvent(capture, 1, LogSinkEventKind.text, "prefix");
    assertEvent(capture, 3, LogSinkEventKind.text, "[info]");
    assertEvent(capture, 6, LogSinkEventKind.messageChunk, "next record");
    assertEvent(capture, 9, LogSinkEventKind.endRecord);
}

// The public sink contract treats chunks as transport fragments, not message
// boundaries. Decorators preserve zero-length and multiple safe chunks without
// combining them or assuming the first chunk is special.
unittest
{
    const style = AnsiStyle.foreground(AnsiColor.brightBlack);
    PrefixProbe probe;
    Capture first;
    Capture second;
    TeeLogSink tee = TeeLogSink.create(
        LogSinkRef.create(&captureSink, &first),
        LogSinkRef.create(&captureSink, &second),
    );
    PrefixLogSink prefixed = PrefixLogSink.create(
        tee.sinkRef(),
        LogPrefixRef.create(&prefixProbe, &probe),
    );
    LogSinkRef sink = prefixed.sinkRef();

    assert(submit(sink, LogSinkEvent.beginRecord()));
    assert(submit(sink, LogSinkEvent.beginMessage(style)));
    assert(submit(sink, LogSinkEvent.messageChunk("a", style)));
    assert(submit(sink, LogSinkEvent.messageChunk("", style)));
    assert(submit(sink, LogSinkEvent.messageChunk("bc", style)));
    assert(submit(sink, LogSinkEvent.endMessage()));
    assert(submit(sink, LogSinkEvent.endRecord()));

    assert(probe.calls == 1);
    assertSameEvents(first, second);
    foreach (capture; [&first, &second])
    {
        assert(capture.count == 9);
        assertEvent(*capture, 0, LogSinkEventKind.beginRecord);
        assertEvent(*capture, 1, LogSinkEventKind.text, "prefix");
        assertEvent(*capture, 2, LogSinkEventKind.text, " ");
        assertEvent(*capture, 3, LogSinkEventKind.beginMessage);
        assert(capture.events[3].style == style);
        assertEvent(*capture, 4, LogSinkEventKind.messageChunk, "a");
        assert(capture.events[4].style == style);
        assertEvent(*capture, 5, LogSinkEventKind.messageChunk, "");
        assert(capture.events[5].style == style);
        assertEvent(*capture, 6, LogSinkEventKind.messageChunk, "bc");
        assert(capture.events[6].style == style);
        assertEvent(*capture, 7, LogSinkEventKind.endMessage);
        assertEvent(*capture, 8, LogSinkEventKind.endRecord);
    }
}

// LogMessageWriter coalesces ordinary fragments and exposes a direct borrowed
// slice path for large input without changing the sink's message lifecycle.
unittest
{
    const style = AnsiStyle.foreground(AnsiColor.brightBlack);
    Capture capture;
    char[8] staging;
    auto writer = createLogMessageWriter(
        LogSinkRef.create(&captureSink, &capture),
        staging[],
        style,
    );

    writer.write("ab");
    writer.write("cd");
    assert(capture.count == 0);
    assert(writer.flush());
    assert(capture.count == 1);
    assertEvent(capture, 0, LogSinkEventKind.messageChunk, "abcd");
    assert(capture.events[0].style == style);
    assert(writer.written == 4);

    // Separate writes that exactly fill staging are emitted automatically.
    writer.write("abc");
    writer.write("defgh");
    assert(capture.count == 2);
    assertEvent(capture, 1, LogSinkEventKind.messageChunk, "abcdefgh");

    const large = "0123456789abcdef";
    writer.write(large);
    assert(capture.count == 3);
    assertEvent(capture, 2, LogSinkEventKind.messageChunk, large);
    assert(capture.events[2].source is large.ptr);
    assert(writer.written == 12 + large.length);
    assert(writer.finish());
    assert(!writer.failed);
}

// A large borrowed write does not get copied merely to fill unused staging
// capacity. Existing staged bytes are emitted first and the large slice keeps
// its original address in the following chunk.
unittest
{
    Capture capture;
    char[8] staging;
    auto writer = createLogMessageWriter(
        LogSinkRef.create(&captureSink, &capture),
        staging[],
    );

    writer.write("ab");
    const large = "0123456789";
    writer.write(large);

    assert(capture.count == 2);
    assertEvent(capture, 0, LogSinkEventKind.messageChunk, "ab");
    assertEvent(capture, 1, LogSinkEventKind.messageChunk, large);
    assert(capture.events[1].source is large.ptr);
    assert(writer.finish());
}

// Streaming remains useful with no staging storage: complete borrowed text is
// submitted directly, while an SGR sequence split by producer writes is held
// until it can be emitted as one safe transport chunk.
unittest
{
    Capture capture;
    auto writer = createLogMessageWriter(
        LogSinkRef.create(&captureSink, &capture),
        null,
    );

    writer.write("body");
    assertEvent(capture, 0, LogSinkEventKind.messageChunk, "body");

    writer.write("\x1b[3");
    assert(capture.count == 1);
    assert(writer.flush());
    assert(capture.count == 1);

    writer.write("1mred");
    assert(capture.count == 3);
    assertEvent(capture, 1, LogSinkEventKind.messageChunk, "\x1b[31m");
    assertEvent(capture, 2, LogSinkEventKind.messageChunk, "red");
    assert(writer.finish());
}

// Buffer flushes also preserve SGR sequences when the artificial staging
// boundary lands inside one. A literal incomplete suffix is emitted only when
// finishing the logical message, where no later chunk can complete it.
unittest
{
    Capture capture;
    char[4] staging;
    auto writer = createLogMessageWriter(
        LogSinkRef.create(&captureSink, &capture),
        staging[],
    );

    writer.write("\x1b[3");
    assert(writer.flush());
    assert(capture.count == 0);
    writer.write("1mX");
    assert(capture.count == 1);
    assertEvent(capture, 0, LogSinkEventKind.messageChunk, "\x1b[31m");
    assert(writer.finish());
    assert(capture.count == 2);
    assertEvent(capture, 1, LogSinkEventKind.messageChunk, "X");

    capture.clear();
    auto finalWriter = createLogMessageWriter(
        LogSinkRef.create(&captureSink, &capture),
        staging[],
    );
    finalWriter.write("A\x1b[");
    assert(finalWriter.finish());
    assert(capture.count == 2);
    assertEvent(capture, 0, LogSinkEventKind.messageChunk, "A");
    assertEvent(capture, 1, LogSinkEventKind.messageChunk, "\x1b[");
}

// Empty writes and empty messages do not manufacture transport chunks. The
// zero-state writer is invalid and fails without invoking anything.
unittest
{
    Capture capture;
    char[4] staging;
    auto writer = createLogMessageWriter(
        LogSinkRef.create(&captureSink, &capture),
        staging[],
    );
    writer.write("");
    assert(writer.finish());
    assert(writer.written == 0);
    assert(capture.count == 0);

    LogMessageWriter invalid;
    assert(invalid.failed);
    invalid.write("ignored");
    assert(!invalid.flush());
    assert(capture.count == 0);
}

// Sink rejection is sticky. Bytes from the rejected callback are not counted
// as written and later producer operations do not touch the sink again.
unittest
{
    Capture capture;
    capture.rejectAt = 1;
    char[8] staging;
    auto writer = createLogMessageWriter(
        LogSinkRef.create(&captureSink, &capture),
        staging[],
    );

    const first = "012345678";
    writer.write(first);
    assert(!writer.failed);
    assert(writer.written == first.length);

    writer.write("abcdefgh");
    assert(writer.failed);
    assert(writer.written == first.length);
    assert(capture.count == 2);

    writer.write("ignored");
    assert(!writer.flush());
    assert(!writer.finish());
    assert(capture.count == 2);
}

// Streaming formatting uses the ordinary XTB print semantics while the outer
// message writer still owns chunk coalescing. Primitive values formatted in
// separate calls therefore accumulate in the same message staging buffer.
unittest
{
    Capture capture;
    char[64] staging;
    auto writer = createLogMessageWriter(
        LogSinkRef.create(&captureSink, &capture),
        staging[],
    );

    writer.format(-42);
    writer.write(" ");
    writer.format(true);
    writer.write(" ");
    writer.format('X');
    writer.write(" ");
    writer.format(1.25);
    writer.write(" ");
    writer.format(StreamFormatProbe(7));

    assert(capture.count == 0);
    assert(writer.finish());
    assert(capture.count == 1);
    assertEvent(
        capture,
        0,
        LogSinkEventKind.messageChunk,
        "-42 true X 1.25 probe(7)",
    );
}

// `format` is an adapter over the already-streaming core print Writer rather
// than another value-formatting implementation. Large borrowed strings retain
// their source pointer through both writers and require no complete temporary
// representation.
unittest
{
    ChunkCounter counter;
    char[8] staging;
    auto writer = createLogMessageWriter(
        LogSinkRef.create(&chunkCounterSink, &counter),
        staging[],
    );

    char[600] large;
    foreach (ref character; large)
        character = 'x';
    const String borrowed = cast(String) large[];
    writer.format(borrowed);

    assert(!writer.failed);
    assert(counter.calls == 1);
    assert(counter.bytes == borrowed.length);
    assert(counter.source is borrowed.ptr);
    assert(writer.written == borrowed.length);
    assert(writer.finish());
}

// A rejection reached through the print adapter becomes the same sticky writer
// failure as a raw `write`, and later formatting does not call the sink again.
unittest
{
    ChunkCounter counter;
    counter.rejectAt = 0;
    char[8] staging;
    auto writer = createLogMessageWriter(
        LogSinkRef.create(&chunkCounterSink, &counter),
        staging[],
    );

    char[600] large;
    foreach (ref character; large)
        character = 'x';
    writer.format(cast(String) large[]);
    assert(writer.failed);
    assert(counter.calls == 1);
    assert(writer.written == 0);

    writer.format(42);
    writer.write("ignored");
    assert(counter.calls == 1);
    assert(!writer.finish());
}

// Pretty printing needs no logging-specific formatter. `PrettyValue.formatTo`
// already targets the core streaming Writer, so passing a pretty wrapper to
// `LogMessageWriter.format` preserves exact pretty output across many chunks.
unittest
{
    int[96] values;
    foreach (index, ref value; values)
        value = cast(int) index;

    PrettyPrintOptions options = PrettyPrintOptions.defaults()
        .withoutColors()
        .withLayout(PrettyPrintLayout.expanded);
    options.maxItems = cast(uint) values.length;

    char[8192] expectedStorage;
    const expected = writeBuffer(expectedStorage[], values.pretty(options));
    assert(expected.ok);
    assert(!expected.truncated);

    MessageCapture capture;
    char[13] staging;
    Logger logger = Logger.create(
        LogSinkRef.create(&messageCaptureSink, &capture),
        staging[],
        LogLevel.debug_,
    );
    const result = logger.stream(
        LogLevel.debug_,
        (scope ref LogMessageWriter output) { output.format(values.pretty(options)); },
    );

    assert(result.delivered);
    assert(result.written == expected.written);
    assert(result.required == expected.written);
    assert(capture.chunks > 1);
    assert(capture.maxChunk < expected.written);
    assert(capture.text == expectedStorage[0 .. expected.written]);
}

// A low-level pretty hook that emits one large borrowed slice keeps the same
// zero-copy path as ordinary `format`: the pretty wrapper does not materialize
// an intermediate representation before the log sink sees the bytes.
unittest
{
    char[600] large;
    foreach (ref character; large)
        character = 'p';
    const String payload = cast(String) large[];
    PrettyStreamProbe probe = PrettyStreamProbe(payload);
    const options = PrettyPrintOptions.defaults().withoutColors();

    ChunkCounter counter;
    char[8] staging;
    auto writer = createLogMessageWriter(
        LogSinkRef.create(&chunkCounterSink, &counter),
        staging[],
    );
    writer.format(probe.pretty(options));

    assert(writer.finish());
    assert(!writer.failed);
    assert(counter.calls == 1);
    assert(counter.bytes == payload.length);
    assert(counter.source is payload.ptr);
    assert(writer.written == payload.length);
}

unittest
{
    import core.stdc.stdio : fclose, tmpfile;
    import xtb.core.ansi : AnsiAttribute, AnsiColor, AnsiStyle, ansiReset;
    import xtb.core.utf8 : isValidUtf8;
    import xtb.core.string;

    static assert(is(typeof(&captureSink) == LogSink));
    static assert(is(typeof(&captureFlush) == LogFlush));

    Capture capture;
    capture.flushAccepted = true;
    LogSinkRef sink = LogSinkRef.create(&captureSink, &capture, &captureFlush);
    assert(sink.valid);
    LogSinkRef sinkCopy = sink;
    assert(sinkCopy.valid);

    LogSinkRef invalidSink;
    LogSinkEvent event = LogSinkEvent.beginRecord();
    assert(!invalidSink.valid);
    assert(!invalidSink.submit(&event));
    assert(!invalidSink.flush());
    assert(!sink.submit(null));

    LogSinkEvent directText = LogSinkEvent.text(
        "direct",
        AnsiStyle.foreground(AnsiColor.cyan),
    );
    assert(sink.submit(&directText));
    assert(capture.count == 1);
    assertEvent(capture, 0, LogSinkEventKind.text, "direct");
    assert(capture.events[0].style == directText.style);
    capture.clear();

    char[32] messageBuffer;
    Logger logger = Logger.create(
        sink,
        messageBuffer[],
        LogLevel.debug_,
    );
    assert(logger.valid);
    assert(logger.minimumLevel == LogLevel.debug_);

    assert(logger.log(LogLevel.trace, "hidden").status == LogStatus.filtered);
    assert(capture.count == 0);

    LogResult result = logger.logf!"value={}"(LogLevel.info, 7);
    assert(result.status == LogStatus.delivered);
    const defaults = LogPalette.defaults();
    capture.assertSuccessfulRecord(
        "[info]",
        "value=7",
        defaults.info.label,
        defaults.info.message,
    );

    capture.clear();
    result = logger.log(LogLevel.warning, "message longer than buffer capacity by far");
    assert(result.status == LogStatus.truncated && result.required > result.written);
    assert(capture.count == 8);
    assert(capture.events[4].kind == LogSinkEventKind.messageChunk);
    assert(capture.events[4].length == result.written);
    assert(logger.flush());
    assert(capture.flushCount == 1);

    capture.clear();
    result = logger.info();
    assert(result.status == LogStatus.delivered);
    capture.assertSuccessfulRecord(
        "[info]",
        "",
        defaults.info.label,
        defaults.info.message,
    );

    // Streaming uses the same record framing while allowing many message
    // chunks to be produced from storage much smaller than the full message.
    Capture streamCapture;
    char[4] streamBuffer;
    Logger streamLogger = Logger.create(
        LogSinkRef.create(&captureSink, &streamCapture),
        streamBuffer[],
    );
    size_t streamProducerCalls;
    result = streamLogger.stream(LogLevel.error, (scope ref LogMessageWriter writer) {
        ++streamProducerCalls;
        writer.write("ab");
        writer.write("cd");
        writer.write("ef");
    });
    assert(result.status == LogStatus.delivered);
    assert(result.written == 6 && result.required == 6);
    assert(streamProducerCalls == 1);
    assert(streamCapture.count == 9);
    assertEvent(streamCapture, 0, LogSinkEventKind.beginRecord);
    assertEvent(streamCapture, 1, LogSinkEventKind.text, "[error]");
    assertEvent(streamCapture, 2, LogSinkEventKind.text, " ");
    assertEvent(streamCapture, 3, LogSinkEventKind.beginMessage);
    assertEvent(streamCapture, 4, LogSinkEventKind.messageChunk, "abcd");
    assertEvent(streamCapture, 5, LogSinkEventKind.messageChunk, "ef");
    assertEvent(streamCapture, 6, LogSinkEventKind.endMessage);
    assertEvent(streamCapture, 7, LogSinkEventKind.text, "\n");
    assertEvent(streamCapture, 8, LogSinkEventKind.endRecord);

    // `scope auto ref` keeps stateful/non-copyable producers usable without
    // manufacturing an extra callable copy.
    streamCapture.clear();
    size_t probeCalls;
    StreamProducerProbe streamProbe;
    streamProbe.calls = &probeCalls;
    result = streamLogger.stream(LogLevel.info, streamProbe);
    assert(result.status == LogStatus.delivered);
    assert(probeCalls == 1);
    streamCapture.assertSuccessfulRecord(
        "[info]",
        "non-copyable producer",
        defaults.info.label,
        defaults.info.message,
    );

    streamCapture.clear();
    streamLogger.setMinimumLevel(LogLevel.critical);
    result = streamLogger.stream(LogLevel.info, (scope ref LogMessageWriter writer) {
        ++streamProducerCalls;
        writer.write("must not run");
    });
    assert(result.status == LogStatus.filtered);
    assert(streamProducerCalls == 1);
    assert(streamCapture.count == 0);

    Logger invalidStreamLogger;
    result = invalidStreamLogger.stream(LogLevel.error, (scope ref LogMessageWriter writer) {
        ++streamProducerCalls;
        writer.write("must not run");
    });
    assert(result.status == LogStatus.invalidLogger);
    assert(streamProducerCalls == 1);

    // Every logger-owned lifecycle failure is finalized the same way as the
    // ordinary delivery path. The producer only runs after beginMessage is
    // accepted, and `written` reports the successfully submitted stream prefix.
    foreach (rejectAt; 0 .. 9)
    {
        Capture failedStream;
        failedStream.rejectAt = rejectAt;
        char[4] failedBuffer;
        Logger failedLogger = Logger.create(
            LogSinkRef.create(&captureSink, &failedStream),
            failedBuffer[],
        );
        size_t producerCalls;
        const failedResult = failedLogger.stream(
            LogLevel.error,
            (scope ref LogMessageWriter writer) {
            ++producerCalls;
            writer.write("ab");
            writer.write("cd");
            writer.write("ef");
        },
        );

        if (rejectAt < 9)
            assert(failedResult.status == LogStatus.sinkFailed);
        else
            assert(failedResult.status == LogStatus.delivered);
        assert(producerCalls == (rejectAt >= 4 ? 1 : 0));
        const expectedWritten = rejectAt <= 4 ? 0 : rejectAt == 5 ? 4 : 6;
        assert(failedResult.written == expectedWritten);
        assert(failedResult.required == expectedWritten);
        assertEvent(failedStream, 0, LogSinkEventKind.beginRecord);
        if (rejectAt == 0)
            assert(failedStream.count == 1);
        else
            assert(failedStream.events[failedStream.count - 1].kind ==
                    LogSinkEventKind.endRecord);
        if (rejectAt >= 3)
        {
            bool sawEndMessage;
            foreach (captured; failedStream.events[0 .. failedStream.count])
                sawEndMessage = sawEndMessage ||
                    captured.kind == LogSinkEventKind.endMessage;
            assert(sawEndMessage);
        }
    }

    // A streaming producer executes under the same recursion guard, and the
    // sink reference is frozen for the whole record even if the logger is
    // reconfigured from inside the producer.
    Capture guardedCapture;
    char[8] guardedBuffer;
    Logger guardedLogger = Logger.create(
        LogSinkRef.create(&captureSink, &guardedCapture),
        guardedBuffer[],
    );
    LogStatus nestedStatus;
    result = guardedLogger.stream(LogLevel.error, (scope ref LogMessageWriter writer) {
        nestedStatus = guardedLogger.info("nested").status;
        writer.write("outer");
    });
    assert(result.status == LogStatus.delivered);
    assert(nestedStatus == LogStatus.recursive);
    guardedCapture.assertSuccessfulRecord(
        "[error]",
        "outer",
        defaults.error.label,
        defaults.error.message,
    );

    Capture replacementStreamCapture;
    guardedCapture.clear();
    result = guardedLogger.stream(LogLevel.info, (scope ref LogMessageWriter writer) {
        guardedLogger.setSink(LogSinkRef.create(&captureSink, &replacementStreamCapture));
        writer.write("current");
    });
    assert(result.status == LogStatus.delivered);
    guardedCapture.assertSuccessfulRecord(
        "[info]",
        "current",
        defaults.info.label,
        defaults.info.message,
    );
    assert(replacementStreamCapture.count == 0);
    assert(guardedLogger.info("next").delivered);
    replacementStreamCapture.assertSuccessfulRecord(
        "[info]",
        "next",
        defaults.info.label,
        defaults.info.message,
    );

    // Tee branch failure remains deferred until endRecord, so the writer keeps
    // streaming every later chunk to the healthy peer before reporting failure.
    Capture failedBranch;
    failedBranch.rejectAt = 4;
    Capture healthyBranch;
    TeeLogSink streamTee = TeeLogSink.create(
        LogSinkRef.create(&captureSink, &failedBranch),
        LogSinkRef.create(&captureSink, &healthyBranch),
    );
    char[4] teeStreamBuffer;
    Logger teeStreamLogger = Logger.create(streamTee.sinkRef(), teeStreamBuffer[]);
    result = teeStreamLogger.stream(LogLevel.warning, (scope ref LogMessageWriter writer) {
        writer.write("ab");
        writer.write("cd");
        writer.write("ef");
    });
    assert(result.status == LogStatus.sinkFailed);
    assert(result.written == 6 && result.required == 6);
    assert(healthyBranch.count == 9);
    assertEvent(healthyBranch, 4, LogSinkEventKind.messageChunk, "abcd");
    assertEvent(healthyBranch, 5, LogSinkEventKind.messageChunk, "ef");
    assertEvent(healthyBranch, 6, LogSinkEventKind.endMessage);
    assertEvent(healthyBranch, 7, LogSinkEventKind.text, "\n");
    assertEvent(healthyBranch, 8, LogSinkEventKind.endRecord);
    assertEvent(failedBranch, failedBranch.count - 1, LogSinkEventKind.endRecord);

    logger.setMinimumLevel(LogLevel.trace);

    capture.clear();
    assert(logger.trace("trace").delivered);
    capture.assertSuccessfulRecord("[trace]", "trace", defaults.trace.label, defaults.trace.message);
    capture.clear();
    assert(logger.tracef!"{}"("tracef").delivered);
    capture.assertSuccessfulRecord("[trace]", "tracef", defaults.trace.label, defaults.trace.message);
    capture.clear();
    assert(logger.debug_("debug").delivered);
    capture.assertSuccessfulRecord("[debug]", "debug", defaults.debug_.label, defaults.debug_.message);
    capture.clear();
    assert(logger.debugf!"{}"("debugf").delivered);
    capture.assertSuccessfulRecord("[debug]", "debugf", defaults.debug_.label, defaults.debug_
            .message);
    capture.clear();
    assert(logger.info("info").delivered);
    capture.assertSuccessfulRecord("[info]", "info", defaults.info.label, defaults.info.message);
    capture.clear();
    assert(logger.infof!"{}"("infof").delivered);
    capture.assertSuccessfulRecord("[info]", "infof", defaults.info.label, defaults.info.message);
    capture.clear();
    assert(logger.warning("warning").delivered);
    capture.assertSuccessfulRecord("[warning]", "warning", defaults.warning.label, defaults.warning
            .message);
    capture.clear();
    assert(logger.warningf!"{}"("warningf").delivered);
    capture.assertSuccessfulRecord("[warning]", "warningf", defaults.warning.label, defaults.warning
            .message);
    capture.clear();
    assert(logger.error("error").delivered);
    capture.assertSuccessfulRecord("[error]", "error", defaults.error.label, defaults.error.message);
    capture.clear();
    assert(logger.errorf!"{}"("errorf").delivered);
    capture.assertSuccessfulRecord("[error]", "errorf", defaults.error.label, defaults.error.message);
    capture.clear();
    assert(logger.critical("critical").delivered);
    capture.assertSuccessfulRecord("[critical]", "critical", defaults.critical.label, defaults
            .critical.message);
    capture.clear();
    assert(logger.criticalf!"{}"("criticalf").delivered);
    capture.assertSuccessfulRecord("[critical]", "criticalf", defaults.critical.label, defaults
            .critical.message);

    LogPalette palette = defaults;
    palette.warning.label = AnsiStyle.foreground(AnsiColor.rgb(1, 20, 255)).underline;
    palette.warning.message = AnsiStyle.foreground(AnsiColor.brightBlack).dim;
    logger.setPalette(palette);
    capture.clear();
    assert(logger.warning("styled").delivered);
    capture.assertSuccessfulRecord(
        "[warning]",
        "styled",
        palette.warning.label,
        palette.warning.message,
    );

    logger.setPalette(LogPalettePreset.trueColor);
    const trueColor = LogPalette.preset(LogPalettePreset.trueColor);
    capture.clear();
    assert(logger.error("preset").delivered);
    capture.assertSuccessfulRecord(
        "[error]",
        "preset",
        trueColor.error.label,
        trueColor.error.message,
    );

    Capture replacement;
    replacement.flushAccepted = true;
    logger.setSink(LogSinkRef.create(&captureSink, &replacement, &captureFlush));
    capture.clear();
    assert(logger.info("replacement").delivered);
    assert(capture.count == 0);
    assert(replacement.count != 0);
    replacement.clear();
    logger.setSink(&captureSink, &replacement, &captureFlush);
    assert(logger.info("raw overload").delivered);
    assert(replacement.count != 0);

    Capture currentDuringSwap;
    currentDuringSwap.flushAccepted = true;
    Capture afterSwap;
    afterSwap.flushAccepted = true;
    SinkSwapCapture swap;
    Logger swapping = Logger.create(
        LogSinkRef.create(&swappingSink, &swap),
        messageBuffer[],
    );
    swap.logger = &swapping;
    swap.current = &currentDuringSwap;
    swap.replacement = LogSinkRef.create(&captureSink, &afterSwap);
    assert(swapping.info("current sink completes").delivered);
    currentDuringSwap.assertSuccessfulRecord(
        "[info]",
        "current sink completes",
        defaults.info.label,
        defaults.info.message,
    );
    assert(afterSwap.count == 0);
    assert(swapping.info("replacement next").delivered);
    afterSwap.assertSuccessfulRecord(
        "[info]",
        "replacement next",
        defaults.info.label,
        defaults.info.message,
    );

    Logger invalid;
    assert(invalid.log(LogLevel.info, "ignored").status == LogStatus.invalidLogger);
    assert(!invalid.flush());

    Capture rejected;
    rejected.flushAccepted = false;
    rejected.rejectAt = 4;
    Logger rejecting = Logger.create(
        LogSinkRef.create(&captureSink, &rejected, &captureFlush),
        messageBuffer[],
    );
    assert(rejecting.info("rejected").status == LogStatus.sinkFailed);
    assert(rejected.count == 7);
    assertEvent(rejected, 0, LogSinkEventKind.beginRecord);
    assertEvent(rejected, 4, LogSinkEventKind.messageChunk, "rejected");
    assertEvent(rejected, 5, LogSinkEventKind.endMessage);
    assertEvent(rejected, 6, LogSinkEventKind.endRecord);
    assert(!rejecting.flush());
    assert(rejected.flushCount == 1);

    Capture rejectBegin;
    rejectBegin.flushAccepted = true;
    rejectBegin.rejectAt = 0;
    Logger rejectBeginLogger = Logger.create(
        LogSinkRef.create(&captureSink, &rejectBegin),
        messageBuffer[],
    );
    assert(rejectBeginLogger.info("ignored").status == LogStatus.sinkFailed);
    assert(rejectBegin.count == 1);
    assertEvent(rejectBegin, 0, LogSinkEventKind.beginRecord);

    foreach (rejectAt; 0 .. 8)
    {
        Capture failed;
        failed.flushAccepted = true;
        failed.rejectAt = rejectAt;
        Logger failedLogger = Logger.create(
            LogSinkRef.create(&captureSink, &failed),
            messageBuffer[],
        );
        assert(failedLogger.info("failure matrix").status == LogStatus.sinkFailed);
        assert(failed.count != 0);
        assertEvent(failed, 0, LogSinkEventKind.beginRecord);
        if (rejectAt == 0)
            assert(failed.count == 1);
        else
            assert(failed.events[failed.count - 1].kind == LogSinkEventKind.endRecord);
        if (rejectAt >= 3 && rejectAt <= 5)
        {
            bool sawEndMessage;
            foreach (captured; failed.events[0 .. failed.count])
                sawEndMessage = sawEndMessage ||
                    captured.kind == LogSinkEventKind.endMessage;
            assert(sawEndMessage);
        }
    }

    Capture noFlush;
    noFlush.flushAccepted = true;
    Logger noFlushLogger = Logger.create(
        LogSinkRef.create(&captureSink, &noFlush),
        messageBuffer[],
    );
    assert(noFlushLogger.flush());

    RecursiveCapture recursive;
    recursive.events.flushAccepted = true;
    Logger recursiveLogger = Logger.create(
        LogSinkRef.create(&recursiveSink, &recursive),
        messageBuffer[],
    );
    recursive.logger = &recursiveLogger;
    assert(recursiveLogger.log(LogLevel.error, "outer").status == LogStatus.delivered);
    assert(recursive.nestedStatus == LogStatus.recursive);
    recursive.events.assertSuccessfulRecord(
        "[error]",
        "outer",
        defaults.error.label,
        defaults.error.message,
    );

    {
        FILE* file = tmpfile();
        assert(file !is null);
        char[32] fileMessage;
        Logger plain = fileLogger(
            file,
            fileMessage[],
            LogLevel.info,
            LogStyle.plain,
        );
        assert(plain.info("plain message").delivered);
        assert(plain.flush());
        char[64] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal("[info] plain message\n"));
        assert(fclose(file) == 0);
    }

    {
        FILE* file = tmpfile();
        assert(file !is null);
        char[32] fileMessage;
        Logger colored = fileLogger(
            file,
            fileMessage[],
            LogLevel.info,
            LogStyle.ansi,
        );
        assert(colored.info("default colors").delivered);
        assert(colored.flush());
        char[96] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal(
                "\x1b[32m[info]\x1b[0m default colors\x1b[0m\n",
        ));
        assert(fclose(file) == 0);
    }

    // Streaming integration through both presentation sinks proves that the
    // writer's safe transport boundaries are sufficient for stateless SGR
    // preservation/stripping even when the producer splits an escape sequence.
    {
        FILE* file = tmpfile();
        assert(file !is null);
        char[4] fileMessage;
        Logger plain = fileLogger(
            file,
            fileMessage[],
            LogLevel.info,
            LogStyle.plain,
        );
        assert(plain.stream(LogLevel.info, (scope ref LogMessageWriter writer) {
                writer.write("\x1b[3");
                writer.write("1mred");
                writer.write("\x1b[0m!");
            }).delivered);
        assert(plain.flush());
        char[64] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal("[info] red!\n"));
        assert(fclose(file) == 0);
    }

    {
        FILE* file = tmpfile();
        assert(file !is null);
        char[4] fileMessage;
        Logger colored = fileLogger(
            file,
            fileMessage[],
            LogLevel.info,
            LogStyle.ansi,
        );
        assert(colored.stream(LogLevel.info, (scope ref LogMessageWriter writer) {
                writer.write("\x1b[3");
                writer.write("1mred");
                writer.write("\x1b[0m!");
            }).delivered);
        assert(colored.flush());
        char[96] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal(
                "\x1b[32m[info]\x1b[0m \x1b[31mred\x1b[0m!\x1b[0m\n",
        ));
        assert(fclose(file) == 0);
    }

    {
        LogPalette custom = LogPalette.defaults();
        assert(custom.trace.label.enabled && custom.debug_.label.enabled &&
                custom.info.label.enabled && custom.warning.label.enabled &&
                custom.error.label.enabled && custom.critical.label.enabled);
        assert(!custom.trace.message.enabled && !custom.debug_.message.enabled &&
                !custom.info.message.enabled && !custom.warning.message.enabled &&
                !custom.error.message.enabled && !custom.critical.message.enabled);
        assert(custom.critical.label.has(AnsiAttribute.bold));
        custom.warning.label = AnsiStyle.foreground(AnsiColor.rgb(1, 20, 255))
            .underline;
        custom.warning.message = AnsiStyle.foreground(AnsiColor.brightBlack).dim;
        FILE* file = tmpfile();
        assert(file !is null);
        char[32] fileMessage;
        Logger colored = fileLogger(
            file,
            fileMessage[],
            LogLevel.info,
            LogStyle.ansi,
            custom,
        );
        assert(colored.warning("colored message").delivered);
        assert(colored.flush());
        char[128] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal(
                "\x1b[4;38;2;1;20;255m[warning]\x1b[0m " ~
                "\x1b[2;90mcolored message\x1b[0m\n",
        ));
        assert(fclose(file) == 0);
    }

    {
        LogPalette custom = LogPalette.defaults();
        custom.error.label = AnsiStyle.foreground(AnsiColor.brightMagenta);
        custom.error.message = AnsiStyle.foreground(AnsiColor.brightBlack);
        FILE* file = tmpfile();
        assert(file !is null);
        char[32] fileMessage;
        Logger plain = fileLogger(
            file,
            fileMessage[],
            LogLevel.info,
            LogStyle.plain,
            custom,
        );
        assert(plain.error("plain ignores styles").delivered);
        assert(plain.flush());
        char[64] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal("[error] plain ignores styles\n"));
        assert(fclose(file) == 0);
    }

    // Supported SGR parsing and the bounded suffix rule define the producer-side
    // safe chunk boundary used to keep presentation sinks stateless.
    {
        const complete = "\x1b[38;2;255;100;20m";
        const completeResult = parseSgrPrefix(complete);
        assert(completeResult.kind == SgrParseKind.complete);
        assert(completeResult.length == complete.length);
        assert(!completeResult.fullReset);

        assert(parseSgrPrefix("\x1b[0m").fullReset);
        assert(parseSgrPrefix("\x1b[m").fullReset);
        assert(parseSgrPrefix("\x1b[0;0m").fullReset);
        assert(!parseSgrPrefix("\x1b[39m").fullReset);
        assert(!parseSgrPrefix("\x1b[0;31m").fullReset);
        assert(parseSgrPrefix("\x1b[31J").kind == SgrParseKind.unsupported);
        assert(parseSgrPrefix("\x1b[x").kind == SgrParseKind.unsupported);

        char[160] storage;
        enum prefix = "prefix";
        foreach (cut; 1 .. complete.length)
        {
            foreach (index, value; prefix)
                storage[index] = value;
            foreach (index; 0 .. cut)
                storage[prefix.length + index] = complete[index];
            const length = prefix.length + cut;
            assert(safeSgrPrefixLength(storage[0 .. length]) == prefix.length);
        }

        foreach (index, value; prefix)
            storage[index] = value;
        foreach (index, value; complete)
            storage[prefix.length + index] = value;
        const completeLength = prefix.length + complete.length;
        assert(safeSgrPrefixLength(storage[0 .. completeLength]) == completeLength);

        foreach (index; 0 .. storage.length)
            storage[index] = '1';
        storage[0] = '\x1b';
        storage[1] = '[';
        assert(storage.length > maxSupportedSgrLength);
        assert(safeSgrPrefixLength(storage[]) == storage.length);
    }

    // Plain presentation strips supported message SGR while retaining every
    // ordinary byte and ignoring logger-provided styles.
    {
        FILE* file = tmpfile();
        assert(file !is null);
        char[128] fileMessage;
        Logger plain = Logger.create(
            plainFileLogSink(file),
            fileMessage[],
            LogLevel.info,
        );
        const embedded = AnsiStyle.foreground(AnsiColor.red)
            .withBackground(AnsiColor.blue)
            .bold
            .underline;
        assert(plain.info(
                "ordinary ",
                embedded,
                "styled",
                ansiReset,
                " ordinary ",
                AnsiStyle.foreground(AnsiColor.green),
                "green",
                ansiReset,
        ).delivered);
        assert(plain.flush());
        char[128] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal(
                "[info] ordinary styled ordinary green\n",
        ));
        assert(fclose(file) == 0);
    }

    // With no base message style the ANSI sink has no reset-restoration work:
    // embedded SGR is forwarded byte-for-byte and only the final record reset
    // is added by presentation.
    {
        FILE* file = tmpfile();
        assert(file !is null);
        char[128] fileMessage;
        Logger ansi = Logger.create(
            ansiFileLogSink(file),
            fileMessage[],
            LogLevel.info,
        );
        const embedded = AnsiStyle.foreground(AnsiColor.red)
            .withBackground(AnsiColor.blue)
            .bold
            .underline;
        assert(ansi.info(
                "ordinary ",
                embedded,
                "styled",
                ansiReset,
                " ordinary",
        ).delivered);
        assert(ansi.flush());
        char[160] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal(
                "\x1b[32m[info]\x1b[0m ordinary " ~
                "\x1b[1;4;31;44mstyled\x1b[0m ordinary\x1b[0m\n",
        ));
        assert(fclose(file) == 0);
    }

    // A configured base message style is restored after a complete full reset,
    // but partial resets such as 39m retain their ordinary SGR semantics.
    {
        LogPalette custom = LogPalette.defaults();
        custom.info.message = AnsiStyle.foreground(AnsiColor.brightBlack).dim;
        FILE* file = tmpfile();
        assert(file !is null);
        char[192] fileMessage;
        Logger ansi = Logger.create(
            ansiFileLogSink(file),
            fileMessage[],
            LogLevel.info,
            custom,
        );
        assert(ansi.info(
                "base ",
                AnsiStyle.foreground(AnsiColor.red),
                "red",
                ansiReset,
                " base ",
                "\x1b[39m",
                "default foreground",
        ).delivered);
        assert(ansi.flush());
        char[256] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal(
                "\x1b[32m[info]\x1b[0m " ~
                "\x1b[2;90mbase \x1b[31mred\x1b[0m\x1b[2;90m base " ~
                "\x1b[39mdefault foreground\x1b[0m\n",
        ));
        assert(fclose(file) == 0);
    }

    // Presentation remains correct when the protocol carries several message
    // chunks. The base style is not tied to a first-chunk heuristic.
    {
        const base = AnsiStyle.foreground(AnsiColor.brightBlack);
        FILE* file = tmpfile();
        assert(file !is null);
        LogSinkRef ansi = ansiFileLogSink(file);
        assert(submit(ansi, LogSinkEvent.beginRecord()));
        assert(submit(ansi, LogSinkEvent.beginMessage(base)));
        assert(submit(ansi, LogSinkEvent.messageChunk(
                "first \x1b[31mred",
                base,
            )));
        assert(submit(ansi, LogSinkEvent.messageChunk(
                " continues\x1b[0m",
                base,
            )));
        assert(submit(ansi, LogSinkEvent.messageChunk(" base again", base)));
        assert(submit(ansi, LogSinkEvent.endMessage()));
        assert(submit(ansi, LogSinkEvent.endRecord()));
        assert(ansi.flush());
        char[192] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal(
                "\x1b[90mfirst \x1b[31mred continues\x1b[0m" ~
                "\x1b[90m base again\x1b[0m",
        ));
        assert(fclose(file) == 0);
    }

    {
        FILE* file = tmpfile();
        assert(file !is null);
        LogSinkRef plain = plainFileLogSink(file);
        assert(submit(plain, LogSinkEvent.beginRecord()));
        assert(submit(plain, LogSinkEvent.beginMessage()));
        assert(submit(plain, LogSinkEvent.messageChunk(
                "first \x1b[31mred",
            )));
        assert(submit(plain, LogSinkEvent.messageChunk(
                " continues\x1b[0m second \x1b[1;4;44mstyled\x1b[0m",
            )));
        assert(submit(plain, LogSinkEvent.endMessage()));
        assert(submit(plain, LogSinkEvent.endRecord()));
        assert(plain.flush());
        char[96] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal("first red continues second styled"));
        assert(fclose(file) == 0);
    }

    // All six level labels are independently rendered from the configured
    // label style while message styles remain optional.
    {
        LogPalette custom;
        custom.trace.label = AnsiStyle.foreground(AnsiColor.red);
        custom.debug_.label = AnsiStyle.foreground(AnsiColor.green);
        custom.info.label = AnsiStyle.foreground(AnsiColor.yellow);
        custom.warning.label = AnsiStyle.foreground(AnsiColor.blue);
        custom.error.label = AnsiStyle.foreground(AnsiColor.magenta);
        custom.critical.label = AnsiStyle.foreground(AnsiColor.cyan);
        FILE* file = tmpfile();
        assert(file !is null);
        char[32] fileMessage;
        Logger ansi = Logger.create(
            ansiFileLogSink(file),
            fileMessage[],
            LogLevel.trace,
            custom,
        );
        assert(ansi.trace().delivered);
        assert(ansi.debug_().delivered);
        assert(ansi.info().delivered);
        assert(ansi.warning().delivered);
        assert(ansi.error().delivered);
        assert(ansi.critical().delivered);
        assert(ansi.flush());
        char[256] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal(
                "\x1b[31m[trace]\x1b[0m \x1b[0m\n" ~
                "\x1b[32m[debug]\x1b[0m \x1b[0m\n" ~
                "\x1b[33m[info]\x1b[0m \x1b[0m\n" ~
                "\x1b[34m[warning]\x1b[0m \x1b[0m\n" ~
                "\x1b[35m[error]\x1b[0m \x1b[0m\n" ~
                "\x1b[36m[critical]\x1b[0m \x1b[0m\n",
        ));
        assert(fclose(file) == 0);
    }

    // Large formatter output may span the printer's internal buffering while
    // remaining one borrowed logger message chunk in the current API.
    {
        char[1024] message;
        foreach (index; 0 .. message.length)
            message[index] = cast(char)('a' + index % 26);

        FILE* file = tmpfile();
        assert(file !is null);
        char[2048] fileMessage;
        Logger plain = Logger.create(
            plainFileLogSink(file),
            fileMessage[],
            LogLevel.info,
        );
        const largeResult = plain.info(message[]);
        assert(largeResult.status == LogStatus.delivered);
        assert(largeResult.written == message.length);
        assert(largeResult.required == message.length);
        assert(plain.flush());

        char[1100] output;
        const length = readFileContents(file, output[]);
        assert(length == "[info] ".length + message.length + 1);
        assert(output[0 .. "[info] ".length].equal("[info] "));
        assert(output["[info] ".length .. "[info] ".length + message.length]
                .equal(message[]));
        assert(output[length - 1] == '\n');
        assert(fclose(file) == 0);
    }

    // Truncation never exposes a partial supported SGR suffix to the sink.
    // The formatter buffer itself remains untouched; delivery selects a shorter
    // borrowed slice and LogResult reports that safe length.
    {
        Capture safeCapture;
        safeCapture.flushAccepted = true;
        char[12] smallBuffer;
        Logger safeLogger = Logger.create(
            LogSinkRef.create(&captureSink, &safeCapture),
            smallBuffer[],
        );
        const rgb = AnsiStyle.foreground(AnsiColor.rgb(1, 20, 255));
        const sequence = ansiSequence(rgb);
        const safeResult = safeLogger.info("abc", rgb, "tail");
        assert(safeResult.status == LogStatus.truncated);
        assert(safeResult.written == 3);
        assert(safeResult.required == 3 + sequence.view.length + 4);
        assertEvent(safeCapture, 4, LogSinkEventKind.messageChunk, "abc");
        assert(safeCapture.events[4].source == smallBuffer.ptr);
        assert(smallBuffer[3] == '\x1b');
    }

    // A complete SGR may end exactly at the safe formatter boundary.
    {
        Capture boundaryCapture;
        boundaryCapture.flushAccepted = true;
        char[9] exactBuffer;
        Logger boundaryLogger = Logger.create(
            LogSinkRef.create(&captureSink, &boundaryCapture),
            exactBuffer[],
        );
        const boundaryResult = boundaryLogger.info(
            "abc",
            AnsiStyle.foreground(AnsiColor.red),
            "x",
        );
        assert(boundaryResult.status == LogStatus.truncated);
        assert(boundaryResult.written == 8);
        assert(boundaryResult.required == 9);
        assertEvent(
            boundaryCapture,
            4,
            LogSinkEventKind.messageChunk,
            "abc\x1b[31m",
        );
    }

    // Existing UTF-8 boundary repair composes with ANSI suffix trimming.
    {
        Capture utf8Capture;
        utf8Capture.flushAccepted = true;
        char[8] utf8Buffer;
        Logger utf8Logger = Logger.create(
            LogSinkRef.create(&captureSink, &utf8Capture),
            utf8Buffer[],
        );
        const utf8Result = utf8Logger.info(
            "🙂",
            AnsiStyle.foreground(AnsiColor.red),
            "x",
        );
        assert(utf8Result.status == LogStatus.truncated);
        assert(utf8Result.written == "🙂".length);
        assertEvent(utf8Capture, 4, LogSinkEventKind.messageChunk, "🙂");
        assert(isValidUtf8(cast(const(ubyte)[]) utf8Capture.events[4].text));
    }

    // ANSI truncation emits only the safe formatter prefix and still finishes
    // the logical message with the sink-owned terminal reset.
    {
        FILE* file = tmpfile();
        assert(file !is null);
        char[12] truncatedBuffer;
        Logger ansi = Logger.create(
            ansiFileLogSink(file),
            truncatedBuffer[],
            LogLevel.info,
        );
        const truncationResult = ansi.info(
            "abc",
            AnsiStyle.foreground(AnsiColor.rgb(1, 20, 255)),
            "tail",
        );
        assert(truncationResult.status == LogStatus.truncated);
        assert(truncationResult.written == 3);
        assert(ansi.flush());
        char[96] output;
        const length = readFileContents(file, output[]);
        assert(output[0 .. length].equal(
                "\x1b[32m[info]\x1b[0m abc\x1b[0m\n",
        ));
        assert(fclose(file) == 0);
    }
}

unittest
{
    import core.stdc.stdio : fclose, tmpfile;
    import xtb.core.ansi : AnsiColor, AnsiStyle, ansiReset;
    import xtb.core.string;

    const defaults = LogPalette.defaults();

    // Healthy fan-out reaches both children in deterministic first-then-second
    // order for every lifecycle event.
    {
        OrderedCapture order;
        Capture first;
        first.flushAccepted = true;
        Capture second;
        second.flushAccepted = true;
        OrderedBranch firstBranch = OrderedBranch(&order, &first, 1);
        OrderedBranch secondBranch = OrderedBranch(&order, &second, 2);
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&orderedSink, &firstBranch, &orderedFlush),
            LogSinkRef.create(&orderedSink, &secondBranch, &orderedFlush),
        );
        char[64] storage;
        Logger logger = Logger.create(tee.sinkRef(), storage[], LogLevel.info);
        assert(logger.info("healthy").status == LogStatus.delivered);
        first.assertSuccessfulRecord(
            "[info]",
            "healthy",
            defaults.info.label,
            defaults.info.message,
        );
        second.assertSuccessfulRecord(
            "[info]",
            "healthy",
            defaults.info.label,
            defaults.info.message,
        );
        assert(order.count == 16);
        foreach (index; 0 .. 8)
        {
            assert(order.events[index * 2].branch == 1);
            assert(order.events[index * 2 + 1].branch == 2);
            assert(order.events[index * 2].kind == first.events[index].kind);
            assert(order.events[index * 2 + 1].kind == second.events[index].kind);
        }
        assert(logger.flush());
        assert(first.flushCount == 1);
        assert(second.flushCount == 1);
    }

    // The tee forwards arbitrary safe message chunking without a first-chunk
    // heuristic or presentation knowledge.
    {
        Capture first;
        first.flushAccepted = true;
        Capture second;
        second.flushAccepted = true;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&captureSink, &first),
            LogSinkRef.create(&captureSink, &second),
        );
        LogSinkRef sink = tee.sinkRef();
        LogSinkEvent beginRecord = LogSinkEvent.beginRecord();
        LogSinkEvent beginMessage = LogSinkEvent.beginMessage();
        LogSinkEvent firstChunk = LogSinkEvent.messageChunk("first ");
        LogSinkEvent secondChunk = LogSinkEvent.messageChunk("second");
        LogSinkEvent endMessage = LogSinkEvent.endMessage();
        LogSinkEvent endRecord = LogSinkEvent.endRecord();
        assert(sink.submit(&beginRecord));
        assert(sink.submit(&beginMessage));
        assert(sink.submit(&firstChunk));
        assert(sink.submit(&secondChunk));
        assert(sink.submit(&endMessage));
        assert(sink.submit(&endRecord));
        assert(first.count == 6);
        assert(second.count == 6);
        foreach (capture; [&first, &second])
        {
            assertEvent(*capture, 0, LogSinkEventKind.beginRecord);
            assertEvent(*capture, 1, LogSinkEventKind.beginMessage);
            assertEvent(*capture, 2, LogSinkEventKind.messageChunk, "first ");
            assertEvent(*capture, 3, LogSinkEventKind.messageChunk, "second");
            assertEvent(*capture, 4, LogSinkEventKind.endMessage);
            assertEvent(*capture, 5, LogSinkEventKind.endRecord);
        }
    }

    // A first-branch payload failure is deferred until endRecord. The failed
    // branch gets its required finalizers while the healthy branch completes
    // the full record.
    {
        Capture first;
        first.flushAccepted = true;
        first.rejectAt = 4;
        Capture second;
        second.flushAccepted = true;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&captureSink, &first),
            LogSinkRef.create(&captureSink, &second),
        );
        char[64] storage;
        Logger logger = Logger.create(tee.sinkRef(), storage[]);
        assert(logger.info("first fails").status == LogStatus.sinkFailed);
        assert(first.count == 7);
        assertEvent(first, 4, LogSinkEventKind.messageChunk, "first fails");
        assertEvent(first, 5, LogSinkEventKind.endMessage);
        assertEvent(first, 6, LogSinkEventKind.endRecord);
        second.assertSuccessfulRecord(
            "[info]",
            "first fails",
            defaults.info.label,
            defaults.info.message,
        );
    }

    // Branch health is record-local. A branch that failed one record is tried
    // again from beginRecord on the next record.
    {
        Capture first;
        first.flushAccepted = true;
        first.rejectAt = 4;
        Capture second;
        second.flushAccepted = true;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&captureSink, &first),
            LogSinkRef.create(&captureSink, &second),
        );
        char[64] storage;
        Logger logger = Logger.create(tee.sinkRef(), storage[]);
        assert(logger.info("fails once").status == LogStatus.sinkFailed);
        first.clear();
        second.clear();
        assert(logger.info("recovers").status == LogStatus.delivered);
        first.assertSuccessfulRecord(
            "[info]",
            "recovers",
            defaults.info.label,
            defaults.info.message,
        );
        second.assertSuccessfulRecord(
            "[info]",
            "recovers",
            defaults.info.label,
            defaults.info.message,
        );
    }

    // Failure isolation is symmetric.
    {
        Capture first;
        first.flushAccepted = true;
        Capture second;
        second.flushAccepted = true;
        second.rejectAt = 4;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&captureSink, &first),
            LogSinkRef.create(&captureSink, &second),
        );
        char[64] storage;
        Logger logger = Logger.create(tee.sinkRef(), storage[]);
        assert(logger.info("second fails").status == LogStatus.sinkFailed);
        first.assertSuccessfulRecord(
            "[info]",
            "second fails",
            defaults.info.label,
            defaults.info.message,
        );
        assert(second.count == 7);
        assertEvent(second, 5, LogSinkEventKind.endMessage);
        assertEvent(second, 6, LogSinkEventKind.endRecord);
    }

    // Every event position has defined branch-failure semantics. A branch that
    // accepted beginRecord always sees endRecord, and once beginMessage has been
    // delivered it also sees endMessage even when beginMessage itself rejects.
    // This preserves the direct-logger cleanup contract through composition.
    foreach (failFirst; [true, false])
    {
        foreach (rejectAt; 0 .. 8)
        {
            Capture first;
            first.flushAccepted = true;
            Capture second;
            second.flushAccepted = true;
            if (failFirst)
                first.rejectAt = rejectAt;
            else
                second.rejectAt = rejectAt;
            TeeLogSink tee = TeeLogSink.create(
                LogSinkRef.create(&captureSink, &first),
                LogSinkRef.create(&captureSink, &second),
            );
            char[64] storage;
            Logger logger = Logger.create(tee.sinkRef(), storage[]);
            assert(logger.info("failure matrix").status == LogStatus.sinkFailed);

            const(Capture)* failed = failFirst ? &first : &second;
            const(Capture)* healthy = failFirst ? &second : &first;
            assertSuccessfulRecord(
                *healthy,
                "[info]",
                "failure matrix",
                defaults.info.label,
                defaults.info.message,
            );

            // Composition must not change the failure lifecycle seen by the
            // failing child compared with using that sink directly.
            Capture direct;
            direct.flushAccepted = true;
            direct.rejectAt = rejectAt;
            char[64] directStorage;
            Logger directLogger = Logger.create(
                LogSinkRef.create(&captureSink, &direct),
                directStorage[],
            );
            assert(directLogger.info("failure matrix").status == LogStatus.sinkFailed);
            assertSameEvents(*failed, direct);

            assertEvent(*failed, 0, LogSinkEventKind.beginRecord);
            if (rejectAt == 0)
            {
                assert(failed.count == 1);
            }
            else
            {
                assert(failed.events[failed.count - 1].kind == LogSinkEventKind.endRecord);
                if (rejectAt >= 3 && rejectAt <= 5)
                {
                    bool sawEndMessage;
                    foreach (captured; failed.events[0 .. failed.count])
                        sawEndMessage = sawEndMessage ||
                            captured.kind == LogSinkEventKind.endMessage;
                    assert(sawEndMessage);
                }
            }
        }
    }

    // A child that rejects beginMessage after forwarding it still receives
    // endMessage. This keeps presentation cleanup identical to direct logger
    // delivery even when the sink is composed through a tee.
    {
        FILE* file = tmpfile();
        assert(file !is null);
        ForwardingFailure failure = ForwardingFailure(
            ansiFileLogSink(file),
            LogSinkEventKind.beginMessage,
        );
        Capture healthy;
        healthy.flushAccepted = true;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&forwardingFailureSink, &failure),
            LogSinkRef.create(&captureSink, &healthy),
        );
        LogPalette palette;
        palette.info.message = AnsiStyle.foreground(AnsiColor.green);
        char[64] storage;
        Logger logger = Logger.create(
            tee.sinkRef(),
            storage[],
            LogLevel.info,
            palette,
        );
        assert(logger.info("message not forwarded").status == LogStatus.sinkFailed);
        assert(failure.rejected);
        healthy.assertSuccessfulRecord(
            "[info]",
            "message not forwarded",
            palette.info.label,
            palette.info.message,
        );
        assert(fileFlush(cast(void*) file));

        char[128] output;
        const length = readFileContents(file, output[]);
        const opening = ansiSequence(palette.info.message);
        const reset = ansiResetSequence();
        size_t offset;
        assert(output[offset .. offset + "[info] ".length].equal("[info] "));
        offset += "[info] ".length;
        assert(output[offset .. offset + opening.view.length].equal(opening.view));
        offset += opening.view.length;
        assert(output[offset .. offset + reset.view.length].equal(reset.view));
        offset += reset.view.length;
        assert(offset == length);
        assert(fclose(file) == 0);
    }

    // An invalid child makes the composite invalid for configuration checks,
    // but delivery still reaches the valid branch and reports aggregate failure.
    {
        LogSinkRef invalid;
        Capture healthy;
        healthy.flushAccepted = true;
        TeeLogSink tee = TeeLogSink.create(
            invalid,
            LogSinkRef.create(&captureSink, &healthy),
        );
        assert(!tee.valid);
        char[64] storage;
        Logger logger = Logger.create(tee.sinkRef(), storage[]);
        assert(logger.info("invalid peer").status == LogStatus.sinkFailed);
        healthy.assertSuccessfulRecord(
            "[info]",
            "invalid peer",
            defaults.info.label,
            defaults.info.message,
        );
    }

    // Simultaneous branch failure is aggregated once at record completion and
    // both begun branches are finalized.
    {
        Capture first;
        first.flushAccepted = true;
        first.rejectAt = 4;
        Capture second;
        second.flushAccepted = true;
        second.rejectAt = 4;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&captureSink, &first),
            LogSinkRef.create(&captureSink, &second),
        );
        char[64] storage;
        Logger logger = Logger.create(tee.sinkRef(), storage[]);
        assert(logger.info("both fail").status == LogStatus.sinkFailed);
        assert(first.count == 7);
        assert(second.count == 7);
        assertEvent(first, 5, LogSinkEventKind.endMessage);
        assertEvent(second, 5, LogSinkEventKind.endMessage);
        assertEvent(first, 6, LogSinkEventKind.endRecord);
        assertEvent(second, 6, LogSinkEventKind.endRecord);
    }

    // A branch rejecting beginRecord receives no later events; the other branch
    // still receives the complete record and the aggregate result fails.
    {
        Capture first;
        first.flushAccepted = true;
        first.rejectAt = 0;
        Capture second;
        second.flushAccepted = true;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&captureSink, &first),
            LogSinkRef.create(&captureSink, &second),
        );
        char[64] storage;
        Logger logger = Logger.create(tee.sinkRef(), storage[]);
        assert(logger.info("begin failure").status == LogStatus.sinkFailed);
        assert(first.count == 1);
        assertEvent(first, 0, LogSinkEventKind.beginRecord);
        second.assertSuccessfulRecord(
            "[info]",
            "begin failure",
            defaults.info.label,
            defaults.info.message,
        );
    }

    // Flush always reaches both children, even when the first flush fails.
    {
        Capture first;
        first.flushAccepted = false;
        Capture second;
        second.flushAccepted = true;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&captureSink, &first, &captureFlush),
            LogSinkRef.create(&captureSink, &second, &captureFlush),
        );
        LogSinkRef sink = tee.sinkRef();
        assert(!sink.flush());
        assert(first.flushCount == 1);
        assert(second.flushCount == 1);
    }

    // Healthy nested tees preserve deterministic depth-first branch order.
    {
        OrderedCapture order;
        Capture first;
        first.flushAccepted = true;
        Capture second;
        second.flushAccepted = true;
        Capture third;
        third.flushAccepted = true;
        OrderedBranch firstBranch = OrderedBranch(&order, &first, 1);
        OrderedBranch secondBranch = OrderedBranch(&order, &second, 2);
        OrderedBranch thirdBranch = OrderedBranch(&order, &third, 3);
        TeeLogSink inner = TeeLogSink.create(
            LogSinkRef.create(&orderedSink, &firstBranch),
            LogSinkRef.create(&orderedSink, &secondBranch),
        );
        TeeLogSink outer = TeeLogSink.create(
            inner.sinkRef(),
            LogSinkRef.create(&orderedSink, &thirdBranch),
        );
        char[64] storage;
        Logger logger = Logger.create(outer.sinkRef(), storage[]);
        assert(logger.info("nested order").delivered);
        assert(order.count == 24);
        foreach (index; 0 .. 8)
        {
            assert(order.events[index * 3].branch == 1);
            assert(order.events[index * 3 + 1].branch == 2);
            assert(order.events[index * 3 + 2].branch == 3);
        }
    }

    // Nested tees preserve the same failure isolation.
    {
        Capture first;
        first.flushAccepted = true;
        Capture second;
        second.flushAccepted = true;
        second.rejectAt = 4;
        Capture third;
        third.flushAccepted = true;
        TeeLogSink inner = TeeLogSink.create(
            LogSinkRef.create(&captureSink, &first),
            LogSinkRef.create(&captureSink, &second),
        );
        TeeLogSink outer = TeeLogSink.create(
            inner.sinkRef(),
            LogSinkRef.create(&captureSink, &third),
        );
        char[64] storage;
        Logger logger = Logger.create(outer.sinkRef(), storage[]);
        assert(logger.info("nested").status == LogStatus.sinkFailed);
        first.assertSuccessfulRecord(
            "[info]",
            "nested",
            defaults.info.label,
            defaults.info.message,
        );
        assert(second.count == 7);
        third.assertSuccessfulRecord(
            "[info]",
            "nested",
            defaults.info.label,
            defaults.info.message,
        );
    }

    // One logger formatting pass feeds both branches.
    {
        Capture first;
        first.flushAccepted = true;
        Capture second;
        second.flushAccepted = true;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&captureSink, &first),
            LogSinkRef.create(&captureSink, &second),
        );
        char[64] storage;
        Logger logger = Logger.create(tee.sinkRef(), storage[]);
        size_t calls;
        FormatOnceProbe probe = FormatOnceProbe(&calls);
        assert(logger.info(probe).delivered);
        assert(calls == 1);
        first.assertSuccessfulRecord(
            "[info]",
            "formatted-once",
            defaults.info.label,
            defaults.info.message,
        );
        second.assertSuccessfulRecord(
            "[info]",
            "formatted-once",
            defaults.info.label,
            defaults.info.message,
        );
    }

    // Filtering happens outside the tee and therefore touches neither branch.
    {
        Capture first;
        first.flushAccepted = true;
        Capture second;
        second.flushAccepted = true;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&captureSink, &first),
            LogSinkRef.create(&captureSink, &second),
        );
        char[64] storage;
        Logger logger = Logger.create(tee.sinkRef(), storage[], LogLevel.error);
        size_t calls;
        FormatOnceProbe probe = FormatOnceProbe(&calls);
        assert(logger.info(probe).status == LogStatus.filtered);
        assert(calls == 0);
        assert(first.count == 0);
        assert(second.count == 0);
    }

    // Primary use case: one formatting pass produces rich ANSI terminal bytes
    // and a clean plain-file representation, including logger label styling, a
    // base message color, and embedded message SGR.
    {
        FILE* terminal = tmpfile();
        assert(terminal !is null);
        FILE* logfile = tmpfile();
        assert(logfile !is null);

        LogPalette palette = LogPalette.defaults();
        palette.warning.label = AnsiStyle.foreground(AnsiColor.yellow).bold;
        palette.warning.message = AnsiStyle.foreground(AnsiColor.brightBlack);
        TeeLogSink tee = TeeLogSink.create(
            ansiFileLogSink(terminal),
            plainFileLogSink(logfile),
        );
        char[192] storage;
        Logger logger = Logger.create(
            tee.sinkRef(),
            storage[],
            LogLevel.warning,
            palette,
        );
        assert(logger.warning(
                "base ",
                AnsiStyle.foreground(AnsiColor.green),
                "green",
                ansiReset,
                " base",
        ).delivered);
        assert(logger.flush());

        char[256] terminalOutput;
        const terminalLength = readFileContents(terminal, terminalOutput[]);
        assert(terminalOutput[0 .. terminalLength].equal(
                "\x1b[1;33m[warning]\x1b[0m " ~
                "\x1b[90mbase \x1b[32mgreen\x1b[0m\x1b[90m base\x1b[0m\n",
        ));
        char[128] fileOutput;
        const fileLength = readFileContents(logfile, fileOutput[]);
        assert(fileOutput[0 .. fileLength].equal(
                "[warning] base green base\n",
        ));
        assert(fclose(terminal) == 0);
        assert(fclose(logfile) == 0);
    }

    // Recursion remains a property of the logger, not the tee. A nested call
    // attempted by one child is rejected while the outer record still reaches
    // both children.
    {
        RecursiveCapture recursive;
        recursive.events.flushAccepted = true;
        Capture second;
        second.flushAccepted = true;
        char[64] storage;
        TeeLogSink tee = TeeLogSink.create(
            LogSinkRef.create(&recursiveSink, &recursive),
            LogSinkRef.create(&captureSink, &second),
        );
        Logger logger = Logger.create(tee.sinkRef(), storage[]);
        recursive.logger = &logger;
        assert(logger.info("outer").delivered);
        assert(recursive.nestedStatus == LogStatus.recursive);
        recursive.events.assertSuccessfulRecord(
            "[info]",
            "outer",
            defaults.info.label,
            defaults.info.message,
        );
        second.assertSuccessfulRecord(
            "[info]",
            "outer",
            defaults.info.label,
            defaults.info.message,
        );
    }

    version (Posix)
    {
        import core.sys.posix.pthread : pthread_barrier_destroy,
            pthread_barrier_init, pthread_create, pthread_join, pthread_t;
        import core.sys.posix.sys.types : pthread_barrier_t;

        // Shared file presentation locks span the whole logical record, so two
        // concurrent thread-confined loggers cannot interleave record chunks.
        {
            FILE* file = tmpfile();
            assert(file !is null);
            pthread_barrier_t barrier;
            assert(pthread_barrier_init(&barrier, null, 2) == 0);
            scope (exit)
                assert(pthread_barrier_destroy(&barrier) == 0);

            enum iterations = 128;
            ConcurrentLogContext first = ConcurrentLogContext(
                file,
                'A',
                iterations,
                &barrier,
            );
            ConcurrentLogContext second = ConcurrentLogContext(
                file,
                'B',
                iterations,
                &barrier,
            );
            pthread_t firstThread;
            pthread_t secondThread;
            assert(pthread_create(&firstThread, null, &concurrentLogWorker, &first) == 0);
            assert(pthread_create(&secondThread, null, &concurrentLogWorker, &second) == 0);
            assert(pthread_join(firstThread, null) == 0);
            assert(pthread_join(secondThread, null) == 0);
            assert(first.succeeded);
            assert(second.succeeded);
            assert(fileFlush(cast(void*) file));

            char[32_768] output;
            const length = readFileContents(file, output[]);
            const lineLength = "[info] ".length + 64 + 1;
            assert(length == 2 * iterations * lineLength);
            foreach (lineIndex; 0 .. 2 * iterations)
            {
                const line = output[lineIndex * lineLength .. (lineIndex + 1) * lineLength];
                assert(line[0 .. "[info] ".length].equal("[info] "));
                const marker = line["[info] ".length];
                assert(marker == 'A' || marker == 'B');
                foreach (value; line["[info] ".length .. $ - 1])
                    assert(value == marker);
                assert(line[$ - 1] == '\n');
            }
            assert(fclose(file) == 0);
        }

        // A tee branch that fails after a file sink has begun its record still
        // receives endRecord, so the destination lock is released for another
        // thread. Use ftrylockfile to verify this without a potentially hanging
        // blocking test.
        {
            FILE* file = tmpfile();
            assert(file !is null);
            ForwardingFailure failure = ForwardingFailure(
                plainFileLogSink(file),
                LogSinkEventKind.messageChunk,
            );
            Capture healthy;
            healthy.flushAccepted = true;
            TeeLogSink tee = TeeLogSink.create(
                LogSinkRef.create(&forwardingFailureSink, &failure),
                LogSinkRef.create(&captureSink, &healthy),
            );
            char[64] storage;
            Logger logger = Logger.create(tee.sinkRef(), storage[]);
            assert(logger.info("unlock after failure").status == LogStatus.sinkFailed);
            assert(failure.rejected);
            assertEvent(healthy, 7, LogSinkEventKind.endRecord);

            FileTryLockContext tryLock = FileTryLockContext(file);
            pthread_t thread;
            assert(pthread_create(&thread, null, &fileTryLockWorker, &tryLock) == 0);
            assert(pthread_join(thread, null) == 0);
            assert(tryLock.acquired);
            assert(fclose(file) == 0);
        }
    }
}
