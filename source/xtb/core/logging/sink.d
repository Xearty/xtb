module xtb.core.logging.sink;

nothrow @nogc:

import xtb.core.ansi : AnsiStyle;
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

/// A borrowed event delivered synchronously to a `LogSink`.
///
/// A logical record is delimited by `beginRecord` / `endRecord`. At most one
/// message lifecycle may be open inside that record:
///
/// `beginMessage`, zero or more `messageChunk` events, then `endMessage`.
///
/// Chunk boundaries are transport boundaries only. They do not delimit values,
/// lines, or formatter operations, and sinks must not assume that one chunk is
/// the complete message. Producers that introduce transport boundaries into
/// styled text must not split a supported SGR sequence across two chunks; this
/// lets presentation sinks remain allocation-free and stateless across chunk
/// callbacks. A final chunk may end with an incomplete sequence when those bytes
/// are literally the end of the logical message. The base message
/// style supplied to every chunk must match the active `beginMessage` style.
///
/// `bytes` is meaningful for `text` and `messageChunk`. `style` is meaningful
/// for styled logger-generated `text`, for `beginMessage`, and as the repeated
/// base message style carried by `messageChunk`. Event payloads are borrowed only
/// for the synchronous sink callback and must not escape it.
struct LogSinkEvent
{
nothrow @nogc:

    LogSinkEventKind kind;
    String bytes;
    AnsiStyle style;

    static LogSinkEvent beginRecord()
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.beginRecord);
    }

    static LogSinkEvent text(return scope String bytes, AnsiStyle style = AnsiStyle.init)
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.text, bytes, style);
    }

    static LogSinkEvent beginMessage(AnsiStyle style = AnsiStyle.init)
    pure @safe
    {
        return LogSinkEvent(LogSinkEventKind.beginMessage, null, style);
    }

    /// Creates one borrowed formatter-output chunk.
    ///
    /// A chunk may contain any portion of the logical message, including an
    /// empty portion. A non-final chunk must not split a supported SGR sequence
    /// from the following chunk. `baseStyle` must match the style selected for
    /// the active message and is
    /// repeated so presentation sinks can remain stateless across callbacks.
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

alias LogSink = bool function(void* context, scope const LogSinkEvent* event);
alias LogFlush = bool function(void* context);

/// A copyable, non-owning reference to a log sink and optional flush callback.
struct LogSinkRef
{
nothrow @nogc:

    private LogSink sink_;
    private LogFlush flush_;
    private void* context_;

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

    bool valid() const pure @safe
    {
        return sink_ !is null;
    }

    bool submit(scope const LogSinkEvent* event)
    {
        return valid && event !is null && sink_(context_, event);
    }

    bool flush()
    {
        return valid && (flush_ is null || flush_(context_));
    }
}

package bool submit(scope ref LogSinkRef sink, LogSinkEvent event)
{
    return sink.submit(&event);
}
