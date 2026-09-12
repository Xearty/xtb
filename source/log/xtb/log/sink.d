module xtb.log.sink;

nothrow @nogc:

import xtb.ansi;
import xtb.log.level;
import xtb.types;

enum LogSinkEventKind : u8
{
    begin_record,
    text,
    begin_message,
    message_chunk,
    end_message,
    end_record,
}

/// A borrowed event delivered synchronously to a direct `LogSink`.
///
/// `begin_record` is delivered once while a `LogSinkRef` resolves a direct sink
/// into a `LogRecordRef`. The remaining events are delivered through that
/// resolved record. Composite sinks resolve their children once and therefore
/// do not need to remain in the repeated message-byte path unless they perform
/// real per-write work such as fan-out.
///
/// A logical record contains at most one message lifecycle:
/// `begin_message`, zero or more `message_chunk` events, then `end_message`.
/// `text` is framing/setup output such as prefixes, the level label, separators,
/// or the final newline. `may_contain_ansi` is meaningful only for `text`: when
/// true, presentation sinks must apply the same supported-SGR preservation or
/// stripping policy used for arbitrary message bytes. Logger-owned framing sets
/// it false so ordinary level/separator/newline writes avoid unnecessary scans.
///
/// Chunk boundaries are transport boundaries only. They do not delimit values,
/// lines, or formatter operations, and sinks must not assume that one chunk is
/// the complete message. Producers that introduce transport boundaries into
/// styled text must not split a supported SGR sequence across two chunks.
/// Event payloads are borrowed only for the synchronous callback and must not
/// escape it.
struct LogSinkEvent
{
nothrow @nogc:

    LogSinkEventKind kind;
    String bytes;
    ANSIStyle style;
    bool may_contain_ansi;

    static LogSinkEvent begin_record()
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.begin_record);
    }

    static LogSinkEvent text(
        return scope String bytes,
        ANSIStyle style = ANSIStyle.init,
        bool may_contain_ansi = false,
    )
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.text, bytes, style, may_contain_ansi);
    }

    static LogSinkEvent begin_message(ANSIStyle style = ANSIStyle.init)
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.begin_message, null, style);
    }

    static LogSinkEvent message_chunk(
        return scope String bytes,
        ANSIStyle base_style = ANSIStyle.init,
    )
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.message_chunk, bytes, base_style);
    }

    static LogSinkEvent end_message()
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.end_message);
    }

    static LogSinkEvent end_record()
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.end_record);
    }
}

/// Borrowed source metadata captured at the public logging call site.
///
/// `function_name` refers to compiler-emitted static program data. No source
/// string is allocated or copied by the logger.
struct LogSourceLocation
{
    String function_name;
    usize line;
}

/// Immutable setup information for one logical log record.
///
/// The logger owns the spelling and styling of its standard framing. Sink
/// decorators may transform this value while resolving a branch. A resolved
/// record borrows the setup value for exactly that synchronous record lifetime,
/// so later message writes do not need to traverse setup-only decorators again.
/// A decorator that creates branch-specific information must keep that modified
/// value alive until the returned record ends. Optional source metadata is
/// supplied separately to `LogSinkRef.begin_record`, which lets setup-only
/// decorators remove it for one branch without copying this framing data.
struct LogRecordInfo
{
    LogLevel level;
    String level_label;
    ANSIStyle label_style;
    ANSIStyle message_style;
    usize message_padding = 1;
}

alias LogSink = bool function(void* context, scope const LogSinkEvent* event) nothrow @nogc;
alias LogRecordSink = bool function(void* context, scope const LogSinkEvent* event) nothrow @nogc;
alias LogFlush = bool function(void* context) nothrow @nogc;
alias LogRecordResolver = LogRecordRef function(
    void* context,
    scope return const ref LogRecordInfo info,
    scope return const(LogSourceLocation)* callsite,
) nothrow @nogc;

private String callsite_suffix(usize line, return scope char[] storage)
pure @safe
{
    usize cursor = storage.length;
    storage[--cursor] = ')';
    do
    {
        storage[--cursor] = cast(char)('0' + line % 10);
        line /= 10;
    }
    while (line != 0);
    storage[--cursor] = ':';
    return storage[cursor .. $];
}

/// A short-lived, allocation-free output path for one already-resolved record.
///
/// A record reference is produced by `LogSinkRef.begin_record` and remains valid
/// only until its matching `end_record`. It is deliberately non-copyable because
/// it represents one active lifecycle. Direct sinks use one callback and
/// context. Composite sinks may return a callback backed by stable state in the
/// composite object. Setup-only decorators may return a child's record
/// unchanged and therefore disappear from repeated message writes.
struct LogRecordRef
{
nothrow @nogc:

    LogRecordSink sink;
    void* context;
    const(LogRecordInfo)* info;
    const(LogSourceLocation)* callsite;
    bool frames_message;
    bool message_began;
    bool deferred_failure;

    @disable this(this);

    /// Creates an unframed resolved record layer for a compositional sink.
    ///
    /// The callback receives the active record operations after resolution but
    /// never `begin_record`. It is responsible for forwarding or transforming
    /// those operations and for preserving required finalization.
    static LogRecordRef create(
        LogRecordSink sink,
        void* context,
        scope return const ref LogRecordInfo info,
        scope return const(LogSourceLocation)* callsite,
    )
    {
        return LogRecordRef.create_impl(sink, context, info, callsite, false);
    }

    package(xtb.log) static LogRecordRef create_direct(
        LogSink sink,
        void* context,
        scope return const ref LogRecordInfo info,
        scope return const(LogSourceLocation)* callsite,
    )
    {
        return LogRecordRef.create_impl(sink, context, info, callsite, true);
    }

    private static LogRecordRef create_impl(
        LogRecordSink sink,
        void* context,
        scope return const ref LogRecordInfo info,
        scope return const(LogSourceLocation)* callsite,
        bool frames_message,
    )
    {
        LogRecordRef result;
        result.sink = sink;
        result.context = context;
        result.info = &info;
        result.callsite = callsite;
        result.frames_message = frames_message;
        return result;
    }

    bool valid() const pure @safe
    {
        return this.sink !is null && this.info !is null;
    }

    private bool write_padding(usize count)
    {
        enum String spaces =
            "                                                                ";
        while (count != 0)
        {
            const chunk_length = count < spaces.length ? count : spaces.length;
            if (!this.write_text(spaces[0 .. chunk_length])) return false;
            count -= chunk_length;
        }
        return true;
    }

    /// Emits ANSI-free setup/framing text through this resolved output path.
    /// Use `write_ansi_text` when `bytes` may contain embedded ANSI SGR.
    bool write_text(return scope String bytes, ANSIStyle style = ANSIStyle.init)
    {
        const LogSinkEvent event = LogSinkEvent.text(bytes, style, false);
        return this.submit(&event);
    }

    /// Emits one setup span that may contain supported embedded ANSI SGR.
    ///
    /// ANSI presentation preserves supported SGR and terminates the span with a
    /// full reset; plain presentation removes supported SGR. A supported SGR
    /// sequence must not be split across two writes.
    bool write_ansi_text(return scope String bytes, ANSIStyle style = ANSIStyle.init)
    {
        const LogSinkEvent event = LogSinkEvent.text(bytes, style, true);
        return this.submit(&event);
    }

    /// Begins the message after emitting standard logger framing for direct
    /// presentation records. Composite records delegate the transition to their
    /// resolved children, each of which borrows its branch-specific setup info.
    bool begin_message()
    {
        if (!this.valid || this.message_began) return false;

        if (this.frames_message && this.info.level_label.length != 0)
        {
            if (!this.write_text(this.info.level_label, this.info.label_style)) return false;
            if (!this.write_padding(this.info.message_padding)) return false;
        }

        this.message_began = true;
        const LogSinkEvent event = LogSinkEvent.begin_message(this.info.message_style);
        return this.submit(&event);
    }

    bool message_chunk(return scope String bytes)
    {
        if (!this.valid || !this.message_began) return false;
        const LogSinkEvent event = LogSinkEvent.message_chunk(bytes, this.info.message_style);
        return this.submit(&event);
    }

    bool end_message()
    {
        if (!this.valid || !this.message_began) return false;

        const LogSinkEvent event = LogSinkEvent.end_message();
        const bool accepted = this.submit(&event);
        this.message_began = false;
        if (!accepted) return false;

        // Source context is deliberately trailing auxiliary information. Emit
        // it only after the message style has ended so severity/message color
        // cannot visually separate the level from its message. Dim-only styling
        // keeps the callsite neutral and secondary on ANSI destinations; plain
        // destinations ignore the semantic style.
        if (this.frames_message && this.callsite !is null)
        {
            const callsite_style = ANSIStyle.init.dim;
            if (!this.write_text("  (", callsite_style)) return false;
            if (!this.write_text(this.callsite.function_name, callsite_style)) return false;

            char[32] suffix_storage;
            const String suffix = callsite_suffix(this.callsite.line, suffix_storage[]);
            if (!this.write_text(suffix, callsite_style)) return false;
        }
        return true;
    }

    /// Finalizes this record and reports any failure deferred by a setup-only
    /// decorator in addition to the downstream finalization result.
    bool end_record()
    {
        if (!this.valid) return false;

        bool accepted = true;
        if (this.message_began) accepted = this.end_message() && accepted;

        const LogSinkEvent event = LogSinkEvent.end_record();
        accepted = this.submit(&event) && accepted;
        accepted = accepted && !this.deferred_failure;

        // A resolved record is one-shot. Invalidate the handle after its
        // lifecycle is complete so accidental reuse cannot submit another
        // operation to an already-finalized destination.
        this.sink = null;
        this.context = null;
        this.info = null;
        this.callsite = null;
        this.frames_message = false;
        this.message_began = false;
        this.deferred_failure = false;
        return accepted;
    }

    package(xtb.log) bool submit(scope const LogSinkEvent* event)
    {
        return this.valid && event !is null && this.sink(this.context, event);
    }

    package(xtb.log) bool message_open() const pure @safe
    {
        return this.message_began;
    }

    package(xtb.log) void defer_failure()
    {
        this.deferred_failure = true;
    }
}

/// A copyable, non-owning reference to a log sink and optional flush callback.
///
/// A direct sink created from `LogSink` receives `begin_record` once during
/// resolution and then backs the returned `LogRecordRef` directly. A composite
/// sink created from `LogRecordResolver` resolves its graph itself and returns
/// the minimal per-record path required for later writes.
struct LogSinkRef
{
nothrow @nogc:

    LogSink sink;
    LogRecordResolver resolver;
    LogFlush flush_callback;
    void* context;

    /// Creates a direct sink. This is the simple path for ordinary destinations.
    static LogSinkRef create(
        LogSink sink,
        void* context,
        LogFlush flush = null,
    )
    {
        LogSinkRef result;
        result.sink = sink;
        result.flush_callback = flush;
        result.context = context;
        return result;
    }

    /// Creates a compositional sink whose callback resolves one record.
    static LogSinkRef create(
        LogRecordResolver resolver,
        void* context,
        LogFlush flush = null,
    )
    {
        LogSinkRef result;
        result.resolver = resolver;
        result.flush_callback = flush;
        result.context = context;
        return result;
    }

    bool valid() const pure @safe
    {
        return this.sink !is null || this.resolver !is null;
    }

    /// Resolves this sink for one logical record.
    ///
    /// An invalid return value means setup was rejected. A direct sink first
    /// receives `begin_record`; a composite resolver is responsible for beginning
    /// every child lifecycle represented by the returned record. The resolved
    /// record borrows `info` and `callsite` for its synchronous lifetime. The
    /// optional callsite is passed separately so setup-only decorators can
    /// suppress it for a branch without copying the rest of the record metadata.
    LogRecordRef begin_record(
        scope return const ref LogRecordInfo info,
        scope return const(LogSourceLocation)* callsite = null,
    )
    {
        if (!this.valid) return LogRecordRef.init;

        if (this.resolver !is null) return this.resolver(this.context, info, callsite);

        const LogSinkEvent event = LogSinkEvent.begin_record();
        if (!this.sink(this.context, &event)) return LogRecordRef.init;
        return LogRecordRef.create_direct(this.sink, this.context, info, callsite);
    }

    bool flush()
    {
        return this.valid && (this.flush_callback is null || this.flush_callback(this.context));
    }
}
