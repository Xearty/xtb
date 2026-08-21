module xtb.core.logger;

nothrow @nogc:

import core.stdc.stdio : FILE, fflush, fwrite, stderr, stdout;
import core.stdc.string : memchr;
import xtb.core.ansi : AnsiColor, AnsiSequence, AnsiStyle, ansiResetSequence,
    ansiSequence;
import xtb.core.print : BufferWriteResult, formatBuffer, writeBuffer;
import xtb.core.string;

enum LogLevel : ubyte
{
    trace,
    debug_,
    info,
    warning,
    error,
    critical,
}

enum LogStatus : ubyte
{
    filtered,
    delivered,
    truncated,
    sinkFailed,
    recursive,
    invalidLogger,
}

enum LogStyle : ubyte
{
    plain,
    ansi,
}

/// One presentation choice for a log level.
struct LogLevelStyle
{
    AnsiStyle label;
    AnsiStyle message;
}

/// Built-in log palette choices.
///
/// `basic` uses only the terminal's sixteen configurable ANSI colors and keeps
/// message text unstyled. `extended` uses the 256-color palette and shades
/// message text by severity. `trueColor` uses RGB colors and the same severity
/// brightness progression. The two enhanced presets target dark backgrounds.
enum LogPalettePreset : ubyte
{
    basic,
    extended,
    trueColor,
}

/// Presentation styles selected by log level. The zero value is uncolored.
struct LogPalette
{
nothrow @nogc:

    LogLevelStyle trace;
    LogLevelStyle debug_;
    LogLevelStyle info;
    LogLevelStyle warning;
    LogLevelStyle error;
    LogLevelStyle critical;

    /// Returns one of the built-in palettes.
    static LogPalette preset(LogPalettePreset preset)
    @safe
    {
        final switch (preset)
        {
            case LogPalettePreset.basic:
                return basicPreset();
            case LogPalettePreset.extended:
                return extendedPreset();
            case LogPalettePreset.trueColor:
                return trueColorPreset();
        }
    }

    private static LogPalette basicPreset()
    @safe
    {
        LogPalette result;
        result.trace.label = AnsiStyle.foreground(AnsiColor.brightBlack);
        result.debug_.label = AnsiStyle.foreground(AnsiColor.brightBlue);
        result.info.label = AnsiStyle.foreground(AnsiColor.green);
        result.warning.label = AnsiStyle.foreground(AnsiColor.yellow);
        result.error.label = AnsiStyle.foreground(AnsiColor.brightRed);
        result.critical.label = AnsiStyle.foreground(AnsiColor.brightRed).bold;
        return result;
    }

    private static LogPalette extendedPreset()
    @safe
    {
        LogPalette result;
        result.trace = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(244)).dim,
            AnsiStyle.foreground(AnsiColor.indexed(242)),
        );
        result.debug_ = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(75)),
            AnsiStyle.foreground(AnsiColor.indexed(244)),
        );
        result.info = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(42)),
            AnsiStyle.foreground(AnsiColor.indexed(246)),
        );
        result.warning = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(214)).bold,
            AnsiStyle.foreground(AnsiColor.indexed(248)),
        );
        result.error = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(203)),
            AnsiStyle.foreground(AnsiColor.indexed(250)),
        );
        result.critical = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.indexed(231))
                .withBackground(AnsiColor.indexed(160))
                .bold,
            AnsiStyle.foreground(AnsiColor.indexed(255)),
        );
        return result;
    }

    private static LogPalette trueColorPreset()
    @safe
    {
        LogPalette result;
        result.trace = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(128, 128, 128)).dim,
            AnsiStyle.foreground(AnsiColor.rgb(105, 110, 120)),
        );
        result.debug_ = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(198, 120, 221)),
            AnsiStyle.foreground(AnsiColor.rgb(125, 130, 140)),
        );
        result.info = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(86, 182, 194)),
            AnsiStyle.foreground(AnsiColor.rgb(150, 155, 165)),
        );
        result.warning = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(255, 175, 0)).bold,
            AnsiStyle.foreground(AnsiColor.rgb(175, 180, 190)),
        );
        result.error = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(255, 95, 95)),
            AnsiStyle.foreground(AnsiColor.rgb(205, 210, 220)),
        );
        result.critical = LogLevelStyle(
            AnsiStyle.foreground(AnsiColor.rgb(255, 255, 255))
                .withBackground(AnsiColor.rgb(190, 48, 48))
                .bold,
            AnsiStyle.foreground(AnsiColor.rgb(238, 240, 245)),
        );
        return result;
    }

    /// Returns the portable sixteen-color palette.
    static LogPalette defaults()
    @safe
    {
        return preset(LogPalettePreset.basic);
    }

    LogLevelStyle styleFor(LogLevel level) const
    pure @safe
    {
        final switch (level)
        {
            case LogLevel.trace:
                return trace;
            case LogLevel.debug_:
                return debug_;
            case LogLevel.info:
                return info;
            case LogLevel.warning:
                return warning;
            case LogLevel.error:
                return error;
            case LogLevel.critical:
                return critical;
        }
    }
}

unittest
{
    const basic = LogPalette.preset(LogPalettePreset.basic);
    assert(LogPalette.defaults() == basic);
    assert(ansiSequence(basic.trace.label).view.equal("\x1b[90m"));
    assert(ansiSequence(basic.debug_.label).view.equal("\x1b[94m"));
    assert(ansiSequence(basic.info.label).view.equal("\x1b[32m"));
    assert(ansiSequence(basic.warning.label).view.equal("\x1b[33m"));
    assert(ansiSequence(basic.error.label).view.equal("\x1b[91m"));
    assert(ansiSequence(basic.critical.label).view.equal("\x1b[1;91m"));
    assert(!basic.trace.message.enabled);
    assert(!basic.debug_.message.enabled);
    assert(!basic.info.message.enabled);
    assert(!basic.warning.message.enabled);
    assert(!basic.error.message.enabled);
    assert(!basic.critical.message.enabled);

    const extended = LogPalette.preset(LogPalettePreset.extended);
    assert(ansiSequence(extended.trace.label).view.equal("\x1b[2;38;5;244m"));
    assert(ansiSequence(extended.debug_.label).view.equal("\x1b[38;5;75m"));
    assert(ansiSequence(extended.info.label).view.equal("\x1b[38;5;42m"));
    assert(ansiSequence(extended.warning.label).view.equal("\x1b[1;38;5;214m"));
    assert(ansiSequence(extended.error.label).view.equal("\x1b[38;5;203m"));
    assert(ansiSequence(extended.critical.label).view.equal(
            "\x1b[1;38;5;231;48;5;160m",
    ));
    assert(ansiSequence(extended.trace.message).view.equal("\x1b[38;5;242m"));
    assert(ansiSequence(extended.debug_.message).view.equal("\x1b[38;5;244m"));
    assert(ansiSequence(extended.info.message).view.equal("\x1b[38;5;246m"));
    assert(ansiSequence(extended.warning.message).view.equal("\x1b[38;5;248m"));
    assert(ansiSequence(extended.error.message).view.equal("\x1b[38;5;250m"));
    assert(ansiSequence(extended.critical.message).view.equal("\x1b[38;5;255m"));

    const trueColor = LogPalette.preset(LogPalettePreset.trueColor);
    assert(ansiSequence(trueColor.trace.label).view.equal("\x1b[2;38;2;128;128;128m"));
    assert(ansiSequence(trueColor.debug_.label).view.equal("\x1b[38;2;198;120;221m"));
    assert(ansiSequence(trueColor.info.label).view.equal("\x1b[38;2;86;182;194m"));
    assert(ansiSequence(trueColor.warning.label).view.equal("\x1b[1;38;2;255;175;0m"));
    assert(ansiSequence(trueColor.error.label).view.equal("\x1b[38;2;255;95;95m"));
    assert(ansiSequence(trueColor.critical.label).view.equal(
            "\x1b[1;38;2;255;255;255;48;2;190;48;48m",
    ));
    assert(ansiSequence(trueColor.trace.message).view.equal("\x1b[38;2;105;110;120m"));
    assert(ansiSequence(trueColor.debug_.message).view.equal("\x1b[38;2;125;130;140m"));
    assert(ansiSequence(trueColor.info.message).view.equal("\x1b[38;2;150;155;165m"));
    assert(ansiSequence(trueColor.warning.message).view.equal("\x1b[38;2;175;180;190m"));
    assert(ansiSequence(trueColor.error.message).view.equal("\x1b[38;2;205;210;220m"));
    assert(ansiSequence(trueColor.critical.message).view.equal("\x1b[38;2;238;240;245m"));
}

struct LogResult
{
nothrow @nogc:

    LogStatus status;
    size_t written;
    size_t required;

    bool delivered() const pure @safe
    {
        return status == LogStatus.delivered || status == LogStatus.truncated;
    }
}

/// One event in the explicit log-sink lifecycle protocol.
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

/// Restricted synchronous writer exposed to record-prefix providers.
///
/// Each write becomes one ordinary styled `text` event in an already-begun
/// child record. The writer owns no storage and may only be used for the
/// duration of the prefix callback.
struct LogPrefixWriter
{
nothrow @nogc:

    private LogSinkRef* child_;
    private bool failed_;

    bool write(return scope String bytes, AnsiStyle style = AnsiStyle.init)
    {
        if (failed_ || child_ is null)
            return false;
        LogSinkEvent event = LogSinkEvent.text(bytes, style);
        if ((*child_).submit(&event))
            return true;
        failed_ = true;
        return false;
    }
}

alias LogPrefix = bool function(void* context, LogPrefixWriter* output);

/// A copyable, non-owning reference to a record-prefix provider.
struct LogPrefixRef
{
nothrow @nogc:

    private LogPrefix prefix_;
    private void* context_;

    static LogPrefixRef create(LogPrefix prefix, void* context)
    {
        return LogPrefixRef(prefix, context);
    }

    bool valid() const pure @safe
    {
        return prefix_ !is null;
    }

    bool write(LogPrefixWriter* output)
    {
        return valid && output !is null && prefix_(context_, output);
    }
}

/// A stateful record-prefix decorator over one borrowed child sink.
///
/// The provider runs exactly once after the child accepts `beginRecord` and
/// before the logger's first record event is forwarded. Prefix failure is
/// remembered until `endRecord`, allowing the actual record to continue and
/// its lifecycle to be finalized. The wrapper owns neither child nor provider.
/// Once `sinkRef()` has been taken, this value must remain at a stable address
/// and outlive every use of that reference.
struct PrefixLogSink
{
nothrow @nogc:

    private LogSinkRef child_;
    private LogPrefixRef prefix_;
    private bool inRecord_;
    private bool childRecordBegan_;
    private bool childMessageOpen_;
    private bool prefixFailed_;

    @disable this(this);

    static PrefixLogSink create(LogSinkRef child, LogPrefixRef prefix)
    {
        PrefixLogSink result;
        result.child_ = child;
        result.prefix_ = prefix;
        return result;
    }

    bool valid() const pure @safe
    {
        return child_.valid && prefix_.valid;
    }

    LogSinkRef sinkRef() return @trusted
    {
        return LogSinkRef.create(
            &prefixLogSinkCallback,
            cast(void*)&this,
            &prefixLogFlushCallback,
        );
    }
}

private bool prefixLogSinkCallback(void* context, scope const LogSinkEvent* event)
{
    PrefixLogSink* prefixSink = cast(PrefixLogSink*) context;
    if (prefixSink is null || event is null)
        return false;

    final switch (event.kind)
    {
        case LogSinkEventKind.beginRecord:
        {
            if (prefixSink.inRecord_)
                return false;
            if (!prefixSink.child_.submit(event))
                return false;

            prefixSink.inRecord_ = true;
            prefixSink.childRecordBegan_ = true;
            prefixSink.childMessageOpen_ = false;
            prefixSink.prefixFailed_ = false;

            LogPrefixWriter writer;
            writer.child_ = &prefixSink.child_;
            const providerAccepted = prefixSink.prefix_.write(&writer);
            prefixSink.prefixFailed_ = !providerAccepted || writer.failed_;

            // Prefix failure is deliberately deferred until endRecord so the
            // actual record still reaches an already-begun child.
            return true;
        }
        case LogSinkEventKind.beginMessage:
        {
            if (!prefixSink.inRecord_ || prefixSink.childMessageOpen_)
                return false;
            prefixSink.childMessageOpen_ = true;
            return prefixSink.child_.submit(event);
        }
        case LogSinkEventKind.endMessage:
        {
            if (!prefixSink.inRecord_ || !prefixSink.childMessageOpen_)
                return false;
            const accepted = prefixSink.child_.submit(event);
            prefixSink.childMessageOpen_ = false;
            return accepted;
        }
        case LogSinkEventKind.text:
        case LogSinkEventKind.messageChunk:
            return prefixSink.inRecord_ && prefixSink.child_.submit(event);
        case LogSinkEventKind.endRecord:
        {
            if (!prefixSink.inRecord_)
                return false;

            bool accepted = true;
            if (prefixSink.childMessageOpen_)
            {
                LogSinkEvent end = LogSinkEvent.endMessage();
                accepted = prefixSink.child_.submit(&end) && accepted;
                prefixSink.childMessageOpen_ = false;
            }
            if (prefixSink.childRecordBegan_)
            {
                accepted = prefixSink.child_.submit(event) && accepted;
                prefixSink.childRecordBegan_ = false;
            }

            accepted = accepted && !prefixSink.prefixFailed_;
            prefixSink.inRecord_ = false;
            prefixSink.prefixFailed_ = false;
            return accepted;
        }
    }
}

private bool prefixLogFlushCallback(void* context)
{
    PrefixLogSink* prefixSink = cast(PrefixLogSink*) context;
    return prefixSink !is null && prefixSink.child_.flush();
}

/// A stateful two-way fan-out sink over borrowed child sink references.
///
/// The tee is presentation-agnostic. It forwards the explicit sink lifecycle
/// protocol to both children in deterministic first-then-second order. Branch
/// failures are remembered until `endRecord`: a failed branch stops receiving
/// ordinary payload, while a healthy branch continues the record and every
/// branch that successfully began a message/record still receives the matching
/// finalization event.
///
/// `TeeLogSink` owns no child sink or destination. Once `sinkRef()` has been
/// taken, the tee value must remain at a stable address and outlive every use of
/// that reference.
struct TeeLogSink
{
nothrow @nogc:

    private LogSinkRef first_;
    private LogSinkRef second_;
    private bool inRecord_;
    private bool firstRecordBegan_;
    private bool secondRecordBegan_;
    private bool firstMessageOpen_;
    private bool secondMessageOpen_;
    private bool firstHealthy_;
    private bool secondHealthy_;
    private bool recordFailed_;

    @disable this(this);

    static TeeLogSink create(LogSinkRef first, LogSinkRef second)
    {
        TeeLogSink result;
        result.first_ = first;
        result.second_ = second;
        return result;
    }

    bool valid() const pure @safe
    {
        return first_.valid && second_.valid;
    }

    /// Returns a borrowed sink reference backed by this tee.
    LogSinkRef sinkRef() return @trusted
    {
        return LogSinkRef.create(
            &teeLogSinkCallback,
            cast(void*)&this,
            &teeLogFlushCallback,
        );
    }
}

private bool teeSubmitBranch(
    ref LogSinkRef branch,
    ref bool healthy,
    scope const LogSinkEvent* event,
)
{
    if (!healthy)
        return false;
    if (branch.submit(event))
        return true;
    healthy = false;
    return false;
}

private bool teeLogSinkCallback(void* context, scope const LogSinkEvent* event)
{
    TeeLogSink* tee = cast(TeeLogSink*) context;
    if (tee is null || event is null)
        return false;

    final switch (event.kind)
    {
        case LogSinkEventKind.beginRecord:
        {
            if (tee.inRecord_)
                return false;

            tee.inRecord_ = true;
            tee.firstMessageOpen_ = false;
            tee.secondMessageOpen_ = false;
            tee.recordFailed_ = false;

            tee.firstHealthy_ = tee.first_.submit(event);
            tee.firstRecordBegan_ = tee.firstHealthy_;
            tee.secondHealthy_ = tee.second_.submit(event);
            tee.secondRecordBegan_ = tee.secondHealthy_;
            tee.recordFailed_ = !tee.firstHealthy_ || !tee.secondHealthy_;

            // Branch failures are intentionally deferred until endRecord so a
            // healthy branch can still receive the complete logical record.
            return true;
        }
        case LogSinkEventKind.text:
        case LogSinkEventKind.messageChunk:
        {
            if (!tee.inRecord_)
                return false;
            const firstAccepted = teeSubmitBranch(
                tee.first_,
                tee.firstHealthy_,
                event,
            );
            const secondAccepted = teeSubmitBranch(
                tee.second_,
                tee.secondHealthy_,
                event,
            );
            tee.recordFailed_ = tee.recordFailed_ || !firstAccepted || !secondAccepted;
            return true;
        }
        case LogSinkEventKind.beginMessage:
        {
            if (!tee.inRecord_ || tee.firstMessageOpen_ || tee.secondMessageOpen_)
                return false;

            if (tee.firstHealthy_)
            {
                tee.firstMessageOpen_ = true;
                if (!tee.first_.submit(event))
                {
                    tee.firstHealthy_ = false;
                    tee.recordFailed_ = true;
                }
            }
            if (tee.secondHealthy_)
            {
                tee.secondMessageOpen_ = true;
                if (!tee.second_.submit(event))
                {
                    tee.secondHealthy_ = false;
                    tee.recordFailed_ = true;
                }
            }
            return true;
        }
        case LogSinkEventKind.endMessage:
        {
            if (!tee.inRecord_)
                return false;

            if (tee.firstMessageOpen_)
            {
                if (!tee.first_.submit(event))
                {
                    tee.firstHealthy_ = false;
                    tee.recordFailed_ = true;
                }
                tee.firstMessageOpen_ = false;
            }
            if (tee.secondMessageOpen_)
            {
                if (!tee.second_.submit(event))
                {
                    tee.secondHealthy_ = false;
                    tee.recordFailed_ = true;
                }
                tee.secondMessageOpen_ = false;
            }
            return true;
        }
        case LogSinkEventKind.endRecord:
        {
            if (!tee.inRecord_)
                return false;

            // Be defensive for direct protocol users: if a message was begun
            // but endMessage was omitted, finalize it before ending the record.
            if (tee.firstMessageOpen_)
            {
                LogSinkEvent end = LogSinkEvent.endMessage();
                if (!tee.first_.submit(&end))
                    tee.recordFailed_ = true;
                tee.firstMessageOpen_ = false;
            }
            if (tee.secondMessageOpen_)
            {
                LogSinkEvent end = LogSinkEvent.endMessage();
                if (!tee.second_.submit(&end))
                    tee.recordFailed_ = true;
                tee.secondMessageOpen_ = false;
            }

            if (tee.firstRecordBegan_)
            {
                if (!tee.first_.submit(event))
                    tee.recordFailed_ = true;
                tee.firstRecordBegan_ = false;
            }
            if (tee.secondRecordBegan_)
            {
                if (!tee.second_.submit(event))
                    tee.recordFailed_ = true;
                tee.secondRecordBegan_ = false;
            }

            const accepted = !tee.recordFailed_;
            tee.inRecord_ = false;
            tee.firstHealthy_ = false;
            tee.secondHealthy_ = false;
            tee.recordFailed_ = false;
            return accepted;
        }
    }
}

private bool teeLogFlushCallback(void* context)
{
    TeeLogSink* tee = cast(TeeLogSink*) context;
    if (tee is null)
        return false;
    const firstAccepted = tee.first_.flush();
    const secondAccepted = tee.second_.flush();
    return firstAccepted && secondAccepted;
}

struct Logger
{
nothrow @nogc:

    private LogSinkRef sink_;
    private char[] messageBuffer_;
    private LogLevel minimumLevel_;
    private LogPalette palette_;
    private bool delivering_;

    @disable this(this);

    static Logger create(
        LogSinkRef sink,
        return scope char[] messageBuffer,
        LogLevel minimumLevel = LogLevel.info,
        LogPalette palette = LogPalette.defaults(),
    )
    {
        Logger result;
        result.sink_ = sink;
        result.messageBuffer_ = messageBuffer;
        result.minimumLevel_ = minimumLevel;
        result.palette_ = palette;
        return result;
    }

    /// Convenience overload for constructing the borrowed sink descriptor inline.
    static Logger create(
        LogSink sink,
        void* context,
        return scope char[] messageBuffer,
        LogLevel minimumLevel = LogLevel.info,
        LogFlush flush = null,
        LogPalette palette = LogPalette.defaults(),
    )
    {
        return Logger.create(
            LogSinkRef.create(sink, context, flush),
            messageBuffer,
            minimumLevel,
            palette,
        );
    }

    bool valid() const pure @safe
    {
        return sink_.valid;
    }

    LogLevel minimumLevel() const pure @safe
    {
        return minimumLevel_;
    }
}

private String levelLabel(LogLevel level) pure @safe
{
    final switch (level)
    {
        case LogLevel.trace:
            return "[trace]";
        case LogLevel.debug_:
            return "[debug]";
        case LogLevel.info:
            return "[info]";
        case LogLevel.warning:
            return "[warning]";
        case LogLevel.error:
            return "[error]";
        case LogLevel.critical:
            return "[critical]";
    }
}

bool enabled(ref const Logger logger, LogLevel level)
pure @safe
{
    return logger.valid && level >= logger.minimumLevel_;
}

void setMinimumLevel(ref Logger logger, LogLevel level)
{
    logger.minimumLevel_ = level;
}

void setPalette(ref Logger logger, LogPalette palette)
{
    logger.palette_ = palette;
}

/// Selects a built-in palette without constructing it at the call site.
void setPalette(ref Logger logger, LogPalettePreset preset)
{
    logger.setPalette(LogPalette.preset(preset));
}

void setSink(ref Logger logger, LogSinkRef sink)
{
    logger.sink_ = sink;
}

void setSink(
    ref Logger logger,
    LogSink sink,
    void* context,
    LogFlush flush = null,
)
{
    logger.setSink(LogSinkRef.create(sink, context, flush));
}

private bool submit(scope ref LogSinkRef sink, LogSinkEvent event)
{
    return sink.submit(&event);
}

private enum SgrParseKind : ubyte
{
    unsupported,
    incomplete,
    complete,
}

private struct SgrParseResult
{
    SgrParseKind kind;
    size_t length;
    bool fullReset;
}

private enum maxSupportedSgrLength = AnsiSequence.capacity;

private SgrParseResult parseSgrPrefix(scope String bytes)
pure @safe
{
    if (bytes.length == 0 || bytes[0] != '\x1b')
        return SgrParseResult(SgrParseKind.unsupported);
    if (bytes.length == 1)
        return SgrParseResult(SgrParseKind.incomplete);
    if (bytes[1] != '[')
        return SgrParseResult(SgrParseKind.unsupported);

    const limit = bytes.length < maxSupportedSgrLength
        ? bytes.length : maxSupportedSgrLength;
    foreach (index; 2 .. limit)
    {
        const value = cast(ubyte) bytes[index];
        if (value >= 0x40 && value <= 0x7e)
        {
            if (value != 'm')
                return SgrParseResult(SgrParseKind.unsupported);

            bool fullReset = true;
            foreach (parameter; bytes[2 .. index])
            {
                if (parameter != '0' && parameter != ';')
                {
                    fullReset = false;
                    break;
                }
            }
            return SgrParseResult(
                SgrParseKind.complete,
                index + 1,
                fullReset,
            );
        }

        const digit = value >= '0' && value <= '9';
        if (digit || value == ';' || value == ':')
            continue;
        return SgrParseResult(SgrParseKind.unsupported);
    }

    return bytes.length < maxSupportedSgrLength
        ? SgrParseResult(SgrParseKind.incomplete) : SgrParseResult(SgrParseKind.unsupported);
}

private size_t safeSgrPrefixLength(scope String bytes)
pure @safe
{
    if (bytes.length == 0)
        return 0;

    const start = bytes.length > maxSupportedSgrLength
        ? bytes.length - maxSupportedSgrLength : 0;
    size_t index = bytes.length;
    while (index != start)
    {
        --index;
        if (bytes[index] != '\x1b')
            continue;

        const parsed = parseSgrPrefix(bytes[index .. $]);
        return parsed.kind == SgrParseKind.incomplete ? index : bytes.length;
    }
    return bytes.length;
}

private LogResult deliver(
    ref Logger logger,
    LogLevel level,
    BufferWriteResult formatted,
)
{
    if (logger.delivering_)
        return LogResult(LogStatus.recursive, 0, formatted.required);

    LogSinkRef sink = logger.sink_;
    const levelStyle = logger.palette_.styleFor(level);
    const formattedMessage = cast(String) logger.messageBuffer_[0 .. formatted.written];
    const safeWritten = formatted.truncated
        ? safeSgrPrefixLength(formattedMessage) : formatted.written;
    logger.delivering_ = true;
    bool accepted = submit(sink, LogSinkEvent.beginRecord());
    if (!accepted)
    {
        logger.delivering_ = false;
        return LogResult(LogStatus.sinkFailed, safeWritten, formatted.required);
    }

    bool payloadAccepted = submit(sink, LogSinkEvent.text(
            levelLabel(level),
            levelStyle.label,
    ));
    if (payloadAccepted)
        payloadAccepted = submit(sink, LogSinkEvent.text(" "));

    bool messageBegan;
    if (payloadAccepted)
    {
        messageBegan = true;
        payloadAccepted = submit(sink, LogSinkEvent.beginMessage(levelStyle.message));
    }
    if (payloadAccepted && safeWritten != 0)
    {
        payloadAccepted = submit(sink, LogSinkEvent.messageChunk(
                logger.messageBuffer_[0 .. safeWritten],
                levelStyle.message,
        ));
    }

    if (messageBegan)
    {
        const endedMessage = submit(sink, LogSinkEvent.endMessage());
        payloadAccepted = endedMessage && payloadAccepted;
    }
    if (payloadAccepted)
        payloadAccepted = submit(sink, LogSinkEvent.text("\n"));

    const endedRecord = submit(sink, LogSinkEvent.endRecord());
    accepted = payloadAccepted && endedRecord;
    logger.delivering_ = false;

    if (!accepted)
        return LogResult(LogStatus.sinkFailed, safeWritten, formatted.required);
    return LogResult(
        formatted.truncated ? LogStatus.truncated : LogStatus.delivered,
        safeWritten,
        formatted.required,
    );
}

LogResult log(Args...)(
    ref Logger logger,
    LogLevel level,
    auto ref Args args,
)
{
    if (!logger.valid)
        return LogResult(LogStatus.invalidLogger, 0, 0);
    if (level < logger.minimumLevel_)
        return LogResult(LogStatus.filtered, 0, 0);
    if (logger.delivering_)
        return LogResult(LogStatus.recursive, 0, 0);
    const formatted = writeBuffer(logger.messageBuffer_, args);
    return logger.deliver(level, formatted);
}

LogResult logf(string pattern, Args...)(
    ref Logger logger,
    LogLevel level,
    auto ref Args args,
)
{
    if (!logger.valid)
        return LogResult(LogStatus.invalidLogger, 0, 0);
    if (level < logger.minimumLevel_)
        return LogResult(LogStatus.filtered, 0, 0);
    if (logger.delivering_)
        return LogResult(LogStatus.recursive, 0, 0);
    const formatted = formatBuffer!pattern(logger.messageBuffer_, args);
    return logger.deliver(level, formatted);
}

LogResult trace(Args...)(ref Logger logger, auto ref Args args)
{
    return logger.log(LogLevel.trace, args);
}

LogResult tracef(string pattern, Args...)(ref Logger logger, auto ref Args args)
{
    return logger.logf!pattern(LogLevel.trace, args);
}

LogResult debug_(Args...)(ref Logger logger, auto ref Args args)
{
    return logger.log(LogLevel.debug_, args);
}

LogResult debugf(string pattern, Args...)(ref Logger logger, auto ref Args args)
{
    return logger.logf!pattern(LogLevel.debug_, args);
}

LogResult info(Args...)(ref Logger logger, auto ref Args args)
{
    return logger.log(LogLevel.info, args);
}

LogResult infof(string pattern, Args...)(ref Logger logger, auto ref Args args)
{
    return logger.logf!pattern(LogLevel.info, args);
}

LogResult warning(Args...)(ref Logger logger, auto ref Args args)
{
    return logger.log(LogLevel.warning, args);
}

LogResult warningf(string pattern, Args...)(ref Logger logger, auto ref Args args)
{
    return logger.logf!pattern(LogLevel.warning, args);
}

LogResult error(Args...)(ref Logger logger, auto ref Args args)
{
    return logger.log(LogLevel.error, args);
}

LogResult errorf(string pattern, Args...)(ref Logger logger, auto ref Args args)
{
    return logger.logf!pattern(LogLevel.error, args);
}

LogResult critical(Args...)(ref Logger logger, auto ref Args args)
{
    return logger.log(LogLevel.critical, args);
}

LogResult criticalf(string pattern, Args...)(ref Logger logger, auto ref Args args)
{
    return logger.logf!pattern(LogLevel.critical, args);
}

bool flush(ref Logger logger)
{
    return logger.sink_.flush();
}

private bool writeAll(FILE* file, String value)
{
    return value.length == 0 || fwrite(value.ptr, 1, value.length, file) == value.length;
}

private size_t findEscape(scope String bytes, size_t start = 0)
@trusted
{
    if (start >= bytes.length)
        return bytes.length;
    const found = memchr(bytes.ptr + start, '\x1b', bytes.length - start);
    return found is null
        ? bytes.length : cast(const(char)*) found - bytes.ptr;
}

private bool writePlainMessage(FILE* file, scope String bytes)
{
    size_t plainStart;
    size_t searchStart;
    while (searchStart < bytes.length)
    {
        const escape = findEscape(bytes, searchStart);
        if (escape == bytes.length)
            break;

        const parsed = parseSgrPrefix(bytes[escape .. $]);
        if (parsed.kind != SgrParseKind.complete)
        {
            searchStart = escape + 1;
            continue;
        }

        if (!writeAll(file, bytes[plainStart .. escape]))
            return false;
        plainStart = escape + parsed.length;
        searchStart = plainStart;
    }
    return writeAll(file, bytes[plainStart .. $]);
}

private bool writeAnsiMessage(FILE* file, scope String bytes, AnsiStyle baseStyle)
{
    if (!baseStyle.enabled)
        return writeAll(file, bytes);

    const firstEscape = findEscape(bytes);
    if (firstEscape == bytes.length)
        return writeAll(file, bytes);

    const baseSequence = ansiSequence(baseStyle);
    size_t spanStart;
    size_t searchStart = firstEscape;
    while (searchStart < bytes.length)
    {
        const escape = findEscape(bytes, searchStart);
        if (escape == bytes.length)
            break;

        const parsed = parseSgrPrefix(bytes[escape .. $]);
        if (parsed.kind == SgrParseKind.complete && parsed.fullReset)
        {
            const resetEnd = escape + parsed.length;
            if (!writeAll(file, bytes[spanStart .. resetEnd]))
                return false;
            if (!baseSequence.empty && !writeAll(file, baseSequence.view))
                return false;
            spanStart = resetEnd;
            searchStart = resetEnd;
            continue;
        }
        searchStart = escape + 1;
    }
    return writeAll(file, bytes[spanStart .. $]);
}

private bool plainFileSinkCallback(void* context, scope const LogSinkEvent* event)
{
    FILE* file = cast(FILE*) context;
    if (file is null || event is null)
        return false;

    final switch (event.kind)
    {
        case LogSinkEventKind.beginRecord:
            lockFile(file);
            return true;
        case LogSinkEventKind.text:
            return writeAll(file, event.bytes);
        case LogSinkEventKind.messageChunk:
            return writePlainMessage(file, event.bytes);
        case LogSinkEventKind.beginMessage:
        case LogSinkEventKind.endMessage:
            return true;
        case LogSinkEventKind.endRecord:
            unlockFile(file);
            return true;
    }
}

private bool ansiFileSinkCallback(void* context, scope const LogSinkEvent* event)
{
    FILE* file = cast(FILE*) context;
    if (file is null || event is null)
        return false;

    const reset = ansiResetSequence();
    final switch (event.kind)
    {
        case LogSinkEventKind.beginRecord:
            lockFile(file);
            return true;
        case LogSinkEventKind.text:
        {
            const opening = ansiSequence(event.style);
            bool accepted = true;
            if (!opening.empty)
                accepted = writeAll(file, opening.view) && accepted;
            accepted = writeAll(file, event.bytes) && accepted;
            if (!opening.empty)
                accepted = writeAll(file, reset.view) && accepted;
            return accepted;
        }
        case LogSinkEventKind.beginMessage:
        {
            const opening = ansiSequence(event.style);
            return opening.empty || writeAll(file, opening.view);
        }
        case LogSinkEventKind.messageChunk:
            return writeAnsiMessage(file, event.bytes, event.style);
        case LogSinkEventKind.endMessage:
            return writeAll(file, reset.view);
        case LogSinkEventKind.endRecord:
            unlockFile(file);
            return true;
    }
}

private void lockFile(FILE* file)
{
    version (Posix)
    {
        import core.sys.posix.stdio : flockfile;

        flockfile(file);
    }
}

private void unlockFile(FILE* file)
{
    version (Posix)
    {
        import core.sys.posix.stdio : funlockfile;

        funlockfile(file);
    }
}

private bool fileFlush(void* context)
{
    FILE* file = cast(FILE*) context;
    return file !is null && fflush(file) == 0;
}

/// Creates a borrowed plain file presentation sink.
///
/// Logger-generated styles are ignored and supported embedded SGR sequences
/// are removed from message chunks. `file` must remain valid while the returned
/// sink reference is used.
LogSinkRef plainFileLogSink(FILE* file)
{
    return LogSinkRef.create(
        &plainFileSinkCallback,
        cast(void*) file,
        &fileFlush,
    );
}

/// Creates a borrowed ANSI file/terminal presentation sink.
///
/// Logger-generated styles and supported embedded message SGR are preserved.
/// Complete full resets inside a message restore the repeated base message
/// style; an empty base style takes the direct-write path.
/// `file` must remain valid while the returned sink reference is used.
LogSinkRef ansiFileLogSink(FILE* file)
{
    return LogSinkRef.create(
        &ansiFileSinkCallback,
        cast(void*) file,
        &fileFlush,
    );
}

Logger fileLogger(
    FILE* file,
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
    LogPalette palette = LogPalette.defaults(),
)
{
    LogSinkRef sink = style == LogStyle.ansi
        ? ansiFileLogSink(file) : plainFileLogSink(file);
    return Logger.create(sink, messageBuffer, minimumLevel, palette);
}

Logger stderrLogger(
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
    LogPalette palette = LogPalette.defaults(),
)
{
    return fileLogger(
        cast(FILE*) stderr,
        messageBuffer,
        minimumLevel,
        style,
        palette,
    );
}

Logger stdoutLogger(
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
    LogPalette palette = LogPalette.defaults(),
)
{
    return fileLogger(
        cast(FILE*) stdout,
        messageBuffer,
        minimumLevel,
        style,
        palette,
    );
}

version (unittest)
{
    import xtb.core.print : Writer;

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

    // Supported SGR parsing and the bounded suffix rule are deliberately
    // independent of presentation mode.
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
