module xtb.log.sink;

nothrow @nogc:

import xtb.core.ansi : AnsiStyle;
import xtb.log.level : LogLevel;
import xtb.core.string : String;

enum LogSinkEventKind : ubyte
{
    beginRecord,
    text,
    beginMessage,
    messageChunk,
    endMessage,
    endRecord,
}

/// A borrowed event delivered synchronously to a direct `LogSink`.
///
/// `beginRecord` is delivered once while a `LogSinkRef` resolves a direct sink
/// into a `LogRecordRef`. The remaining events are delivered through that
/// resolved record. Composite sinks resolve their children once and therefore
/// do not need to remain in the repeated message-byte path unless they perform
/// real per-write work such as fan-out.
///
/// A logical record contains at most one message lifecycle:
/// `beginMessage`, zero or more `messageChunk` events, then `endMessage`.
/// `text` is framing/setup output such as prefixes, the level label, separators,
/// or the final newline. `mayContainAnsi` is meaningful only for `text`: when
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
    AnsiStyle style;
    bool mayContainAnsi;

    static LogSinkEvent beginRecord()
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.beginRecord);
    }

    static LogSinkEvent text(
        return scope String bytes,
        AnsiStyle style = AnsiStyle.init,
        bool mayContainAnsi = false,
    )
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.text, bytes, style, mayContainAnsi);
    }

    static LogSinkEvent beginMessage(AnsiStyle style = AnsiStyle.init)
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.beginMessage, null, style);
    }

    static LogSinkEvent messageChunk(
        return scope String bytes,
        AnsiStyle baseStyle = AnsiStyle.init,
    )
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.messageChunk, bytes, baseStyle);
    }

    static LogSinkEvent endMessage()
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.endMessage);
    }

    static LogSinkEvent endRecord()
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.endRecord);
    }
}

/// Borrowed source metadata captured at the public logging call site.
///
/// `functionName` refers to compiler-emitted static program data. No source
/// string is allocated or copied by the logger.
struct LogSourceLocation
{
    String functionName;
    size_t line;
}

/// Immutable setup information for one logical log record.
///
/// The logger owns the spelling and styling of its standard framing. Sink
/// decorators may transform this value while resolving a branch. A resolved
/// record borrows the setup value for exactly that synchronous record lifetime,
/// so later message writes do not need to traverse setup-only decorators again.
/// A decorator that creates branch-specific information must keep that modified
/// value alive until the returned record ends. Optional source metadata is
/// supplied separately to `LogSinkRef.beginRecord`, which lets setup-only
/// decorators remove it for one branch without copying this framing data.
struct LogRecordInfo
{
    LogLevel level;
    String levelLabel;
    AnsiStyle labelStyle;
    AnsiStyle messageStyle;
    size_t messagePadding = 1;
}

private String callsiteSuffix(size_t line, return scope char[] storage)
pure @safe
{
    size_t cursor = storage.length;
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

alias LogSink = bool function(void* context, scope const LogSinkEvent* event);
alias LogRecordSink = bool function(void* context, scope const LogSinkEvent* event);
alias LogFlush = bool function(void* context);
alias LogRecordResolver = LogRecordRef function(
    void* context,
    scope return const ref LogRecordInfo info,
    scope return const(LogSourceLocation)* callsite,
);

/// A short-lived, allocation-free output path for one already-resolved record.
///
/// A record reference is produced by `LogSinkRef.beginRecord` and remains valid
/// only until its matching `endRecord`. It is deliberately non-copyable because
/// it represents one active lifecycle. Direct sinks use one callback and
/// context. Composite sinks may return a callback backed by stable state in the
/// composite object. Setup-only decorators may return a child's record
/// unchanged and therefore disappear from repeated message writes.
struct LogRecordRef
{
nothrow @nogc:

    @disable this(this);

    private LogRecordSink sink_;
    private void* context_;
    private const(LogRecordInfo)* info_;
    private const(LogSourceLocation)* callsite_;
    private bool framesMessage_;
    private bool messageBegan_;
    private bool deferredFailure_;

    /// Creates an unframed resolved record layer for a compositional sink.
    ///
    /// The callback receives the active record operations after resolution but
    /// never `beginRecord`. It is responsible for forwarding or transforming
    /// those operations and for preserving required finalization.
    static LogRecordRef create(
        LogRecordSink sink,
        void* context,
        scope return const ref LogRecordInfo info,
        scope return const(LogSourceLocation)* callsite,
    )
    {
        return createImpl(sink, context, info, callsite, false);
    }

    package static LogRecordRef createDirect(
        LogSink sink,
        void* context,
        scope return const ref LogRecordInfo info,
        scope return const(LogSourceLocation)* callsite,
    )
    {
        return createImpl(sink, context, info, callsite, true);
    }

    private static LogRecordRef createImpl(
        LogRecordSink sink,
        void* context,
        scope return const ref LogRecordInfo info,
        scope return const(LogSourceLocation)* callsite,
        bool framesMessage,
    )
    {
        LogRecordRef result;
        result.sink_ = sink;
        result.context_ = context;
        result.info_ = &info;
        result.callsite_ = callsite;
        result.framesMessage_ = framesMessage;
        return result;
    }

    bool valid() const pure @safe
    {
        return sink_ !is null && info_ !is null;
    }

    private bool writePadding(size_t count)
    {
        enum String spaces =
            "                                                                ";
        while (count != 0)
        {
            const chunkLength = count < spaces.length ? count : spaces.length;
            if (!writeText(spaces[0 .. chunkLength]))
                return false;
            count -= chunkLength;
        }
        return true;
    }

    /// Emits ANSI-free setup/framing text through this resolved output path.
    /// Use `writeAnsiText` when `bytes` may contain embedded ANSI SGR.
    bool writeText(return scope String bytes, AnsiStyle style = AnsiStyle.init)
    {
        LogSinkEvent event = LogSinkEvent.text(bytes, style, false);
        return submit(&event);
    }

    /// Emits one setup span that may contain supported embedded ANSI SGR.
    ///
    /// ANSI presentation preserves supported SGR and terminates the span with a
    /// full reset; plain presentation removes supported SGR. A supported SGR
    /// sequence must not be split across two writes.
    bool writeAnsiText(return scope String bytes, AnsiStyle style = AnsiStyle.init)
    {
        LogSinkEvent event = LogSinkEvent.text(bytes, style, true);
        return submit(&event);
    }

    /// Begins the message after emitting standard logger framing for direct
    /// presentation records. Composite records delegate the transition to their
    /// resolved children, each of which borrows its branch-specific setup info.
    bool beginMessage()
    {
        if (!valid || messageBegan_)
            return false;

        if (framesMessage_ && info_.levelLabel.length != 0)
        {
            if (!writeText(info_.levelLabel, info_.labelStyle))
                return false;
            if (!writePadding(info_.messagePadding))
                return false;
        }

        messageBegan_ = true;
        LogSinkEvent event = LogSinkEvent.beginMessage(info_.messageStyle);
        return submit(&event);
    }

    bool messageChunk(return scope String bytes)
    {
        if (!valid || !messageBegan_)
            return false;
        LogSinkEvent event = LogSinkEvent.messageChunk(bytes, info_.messageStyle);
        return submit(&event);
    }

    bool endMessage()
    {
        if (!valid || !messageBegan_)
            return false;

        LogSinkEvent event = LogSinkEvent.endMessage();
        const accepted = submit(&event);
        messageBegan_ = false;
        if (!accepted)
            return false;

        // Source context is deliberately trailing auxiliary information. Emit
        // it only after the message style has ended so severity/message color
        // cannot visually separate the level from its message. Dim-only styling
        // keeps the callsite neutral and secondary on ANSI destinations; plain
        // destinations ignore the semantic style.
        if (framesMessage_ && callsite_ !is null)
        {
            const callsiteStyle = AnsiStyle.init.dim;
            if (!writeText("  (", callsiteStyle))
                return false;
            if (!writeText(callsite_.functionName, callsiteStyle))
                return false;

            char[32] suffixStorage;
            const suffix = callsiteSuffix(callsite_.line, suffixStorage[]);
            if (!writeText(suffix, callsiteStyle))
                return false;
        }
        return true;
    }

    /// Finalizes this record and reports any failure deferred by a setup-only
    /// decorator in addition to the downstream finalization result.
    bool endRecord()
    {
        if (!valid)
            return false;

        bool accepted = true;
        if (messageBegan_)
            accepted = endMessage() && accepted;

        LogSinkEvent event = LogSinkEvent.endRecord();
        accepted = submit(&event) && accepted;
        accepted = accepted && !deferredFailure_;

        // A resolved record is one-shot. Invalidate the handle after its
        // lifecycle is complete so accidental reuse cannot submit another
        // operation to an already-finalized destination.
        sink_ = null;
        context_ = null;
        info_ = null;
        callsite_ = null;
        framesMessage_ = false;
        messageBegan_ = false;
        deferredFailure_ = false;
        return accepted;
    }

    package bool submit(scope const LogSinkEvent* event)
    {
        return valid && event !is null && sink_(context_, event);
    }

    package bool messageOpen() const pure @safe
    {
        return messageBegan_;
    }

    package void deferFailure()
    {
        deferredFailure_ = true;
    }
}

/// A copyable, non-owning reference to a log sink and optional flush callback.
///
/// A direct sink created from `LogSink` receives `beginRecord` once during
/// resolution and then backs the returned `LogRecordRef` directly. A composite
/// sink created from `LogRecordResolver` resolves its graph itself and returns
/// the minimal per-record path required for later writes.
struct LogSinkRef
{
nothrow @nogc:

    private LogSink sink_;
    private LogRecordResolver resolver_;
    private LogFlush flush_;
    private void* context_;

    /// Creates a direct sink. This is the simple path for ordinary destinations.
    static LogSinkRef create(
        LogSink sink,
        void* context,
        LogFlush flush = null,
    )
    {
        LogSinkRef result;
        result.sink_ = sink;
        result.flush_ = flush;
        result.context_ = context;
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
        result.resolver_ = resolver;
        result.flush_ = flush;
        result.context_ = context;
        return result;
    }

    bool valid() const pure @safe
    {
        return sink_ !is null || resolver_ !is null;
    }

    /// Resolves this sink for one logical record.
    ///
    /// An invalid return value means setup was rejected. A direct sink first
    /// receives `beginRecord`; a composite resolver is responsible for beginning
    /// every child lifecycle represented by the returned record. The resolved
    /// record borrows `info` and `callsite` for its synchronous lifetime. The
    /// optional callsite is passed separately so setup-only decorators can
    /// suppress it for a branch without copying the rest of the record metadata.
    LogRecordRef beginRecord(
        scope return const ref LogRecordInfo info,
        scope return const(LogSourceLocation)* callsite = null,
    )
    {
        if (!valid)
            return LogRecordRef.init;

        if (resolver_ !is null)
            return resolver_(context_, info, callsite);

        LogSinkEvent event = LogSinkEvent.beginRecord();
        if (!sink_(context_, &event))
            return LogRecordRef.init;
        return LogRecordRef.createDirect(sink_, context_, info, callsite);
    }

    bool flush()
    {
        return valid && (flush_ is null || flush_(context_));
    }
}
