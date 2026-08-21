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
/// `bytes` is meaningful for `text` and `messageChunk`. `style` is meaningful
/// for styled logger-generated `text`, for `beginMessage`, and as the
/// optional base message style carried by `messageChunk`.
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
    /// `baseStyle` must match the style selected for the active message. It is
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
