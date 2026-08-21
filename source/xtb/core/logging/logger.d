module xtb.core.logging.logger;

nothrow @nogc:

import xtb.core.logging.level : LogLevel;
import xtb.core.logging.palette : LogPalette, LogPalettePreset;
import xtb.core.logging.result : LogResult, LogStatus;
import xtb.core.logging.sgr : safeSgrPrefixLength;
import xtb.core.logging.sink : LogFlush, LogSink, LogSinkEvent, LogSinkRef, submit;
import xtb.core.logging.writer : LogMessageWriter, createLogMessageWriter;
import xtb.core.print : BufferWriteResult, formatBuffer, writeBuffer;
import xtb.core.string : String;

struct Logger
{
nothrow @nogc:

    private LogSinkRef sink_;
    private char[] messageBuffer_;
    private LogLevel minimumLevel_;
    private LogPalette palette_;
    private bool delivering_;

    @disable this(this);

    /// Creates a logger borrowing both `sink` and `messageBuffer`.
    ///
    /// `messageBuffer` bounds the complete message produced by `log` / `logf`
    /// and their level-specific wrappers. `stream` instead reuses it only as
    /// staging storage, so a streamed message is not size-limited by the buffer.
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

/// Explicitly emits one unbounded synchronous message incrementally.
///
/// Unlike `log` / `logf`, the complete message does not need to fit in
/// `messageBuffer`. Use this path when unbounded diagnostic output is deliberate;
/// ordinary logging remains bounded by the logger buffer.
///
/// `producer` is invoked exactly once after the sink has accepted the record
/// framing and message begin event. It receives a borrowed `LogMessageWriter`
/// that reuses this logger's message buffer as staging storage and is valid only
/// for the duration of the call. Filtering, an invalid logger, recursion, or a
/// sink failure before the message begins prevent the producer from running.
/// The record lifecycle stays open while `producer` executes, so a sink that
/// serializes records may hold its record lock for the producer's full duration.
///
/// On success, `written` and `required` both report the message bytes accepted
/// by the sink. On sink failure they report the successfully accepted streamed
/// prefix; unlike bounded formatting, a stream has no separately knowable full
/// required length after output has stopped.
LogResult stream(Producer)(
    ref Logger logger,
    LogLevel level,
    scope auto ref Producer producer,
)
{
    if (!logger.valid)
        return LogResult(LogStatus.invalidLogger, 0, 0);
    if (level < logger.minimumLevel_)
        return LogResult(LogStatus.filtered, 0, 0);
    if (logger.delivering_)
        return LogResult(LogStatus.recursive, 0, 0);

    LogSinkRef sink = logger.sink_;
    const levelStyle = logger.palette_.styleFor(level);
    logger.delivering_ = true;

    bool accepted = submit(sink, LogSinkEvent.beginRecord());
    if (!accepted)
    {
        logger.delivering_ = false;
        return LogResult(LogStatus.sinkFailed, 0, 0);
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

    size_t written;
    if (payloadAccepted)
    {
        auto writer = createLogMessageWriter(
            sink,
            logger.messageBuffer_,
            levelStyle.message,
        );
        producer(writer);
        payloadAccepted = writer.finish();
        written = writer.written;
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

    return LogResult(
        accepted ? LogStatus.delivered : LogStatus.sinkFailed,
        written,
        written,
    );
}

/// Emits one bounded message.
///
/// Formatting completes into `messageBuffer` before the sink record begins. If
/// the representation does not fit, the delivered prefix is reported as
/// `LogStatus.truncated`. Use `stream` for deliberate unbounded output.
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

/// Formats and emits one bounded message.
///
/// Formatting completes into `messageBuffer` before the sink record begins. If
/// the representation does not fit, the delivered prefix is reported as
/// `LogStatus.truncated`. Use `stream` for deliberate unbounded output.
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
