module xtb.core.logging.logger;

nothrow @nogc:

import xtb.core.logging.level : LogLevel;
import xtb.core.logging.palette : LogPalette, LogPalettePreset;
import xtb.core.logging.result : LogResult, LogStatus;
import xtb.core.logging.sgr : safeSgrPrefixLength;
import xtb.core.logging.sink : LogFlush, LogRecordInfo, LogRecordRef, LogSink, LogSinkRef,
    LogSourceLocation;
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
    private bool callsitesEnabled_;
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

    /// Returns whether new records include the public caller's function/line.
    bool callsitesEnabled() const pure @safe
    {
        return callsitesEnabled_;
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

/// Enables or disables source-location capture for subsequently emitted records.
///
/// Capture is disabled by default. Enabling it adds static `__FUNCTION__` data
/// and `__LINE__` to record setup; it performs no allocation or stack walk.
void setCallsitesEnabled(ref Logger logger, bool enabled)
{
    logger.callsitesEnabled_ = enabled;
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

private LogRecordInfo recordInfo(ref const Logger logger, LogLevel level)
pure @safe
{
    const style = logger.palette_.styleFor(level);
    return LogRecordInfo(
        level,
        levelLabel(level),
        style.label,
        style.message,
    );
}

private LogResult deliver(
    ref Logger logger,
    LogLevel level,
    BufferWriteResult formatted,
    LogSourceLocation callsite,
)
{
    if (logger.delivering_)
        return LogResult(LogStatus.recursive, 0, formatted.required);

    LogSinkRef sink = logger.sink_;
    const info = recordInfo(logger, level);
    const callsitePtr = logger.callsitesEnabled_ ? &callsite : null;
    const formattedMessage = cast(String) logger.messageBuffer_[0 .. formatted.written];
    const safeWritten = formatted.truncated
        ? safeSgrPrefixLength(formattedMessage) : formatted.written;
    logger.delivering_ = true;

    LogRecordRef record = sink.beginRecord(info, callsitePtr);
    if (!record.valid)
    {
        logger.delivering_ = false;
        return LogResult(LogStatus.sinkFailed, safeWritten, formatted.required);
    }

    bool payloadAccepted = record.beginMessage();
    if (payloadAccepted && safeWritten != 0)
        payloadAccepted = record.messageChunk(logger.messageBuffer_[0 .. safeWritten]);

    if (record.messageOpen)
    {
        const endedMessage = record.endMessage();
        payloadAccepted = endedMessage && payloadAccepted;
    }
    if (payloadAccepted)
        payloadAccepted = record.writeText("\n");

    const endedRecord = record.endRecord();
    const accepted = payloadAccepted && endedRecord;
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
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    if (!logger.valid)
        return LogResult(LogStatus.invalidLogger, 0, 0);
    if (level < logger.minimumLevel_)
        return LogResult(LogStatus.filtered, 0, 0);
    if (logger.delivering_)
        return LogResult(LogStatus.recursive, 0, 0);

    LogSinkRef sink = logger.sink_;
    const info = recordInfo(logger, level);
    const callsitePtr = logger.callsitesEnabled_ ? &callsite : null;
    logger.delivering_ = true;

    LogRecordRef record = sink.beginRecord(info, callsitePtr);
    if (!record.valid)
    {
        logger.delivering_ = false;
        return LogResult(LogStatus.sinkFailed, 0, 0);
    }

    bool payloadAccepted = record.beginMessage();
    size_t written;
    if (payloadAccepted)
    {
        auto writer = createLogMessageWriter(
            &record,
            logger.messageBuffer_,
        );
        producer(writer);
        payloadAccepted = writer.finish();
        written = writer.written;
    }

    if (record.messageOpen)
    {
        const endedMessage = record.endMessage();
        payloadAccepted = endedMessage && payloadAccepted;
    }
    if (payloadAccepted)
        payloadAccepted = record.writeText("\n");

    const endedRecord = record.endRecord();
    const accepted = payloadAccepted && endedRecord;
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
/// `LogStatus.truncated`. Use `stream` for deliberate unbounded output. The
/// trailing default source argument captures this public call site and is only
/// rendered when callsites are enabled on the logger.
LogResult log(Args...)(
    ref Logger logger,
    LogLevel level,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logAt!Args(logger, level, callsite, args);
}

/// Formats and emits one bounded message.
///
/// Formatting completes into `messageBuffer` before the sink record begins. If
/// the representation does not fit, the delivered prefix is reported as
/// `LogStatus.truncated`. Use `stream` for deliberate unbounded output. The
/// trailing default source argument captures this public call site and is only
/// rendered when callsites are enabled on the logger.
LogResult logf(string pattern, Args...)(
    ref Logger logger,
    LogLevel level,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logfAt!(pattern, Args)(logger, level, callsite, args);
}

// Forwarding layers use a fixed callsite parameter before the variadic message
// arguments. This keeps an empty Args tuple unambiguous: a forwarded
// LogSourceLocation can never be re-deduced as message data.
package LogResult logAt(Args...)(
    ref Logger logger,
    LogLevel level,
    LogSourceLocation callsite,
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
    return logger.deliver(level, formatted, callsite);
}

package LogResult logfAt(string pattern, Args...)(
    ref Logger logger,
    LogLevel level,
    LogSourceLocation callsite,
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
    return logger.deliver(level, formatted, callsite);
}

LogResult trace(Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logAt!Args(logger, LogLevel.trace, callsite, args);
}

LogResult tracef(string pattern, Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logfAt!(pattern, Args)(logger, LogLevel.trace, callsite, args);
}

LogResult debug_(Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logAt!Args(logger, LogLevel.debug_, callsite, args);
}

LogResult debugf(string pattern, Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logfAt!(pattern, Args)(logger, LogLevel.debug_, callsite, args);
}

LogResult info(Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logAt!Args(logger, LogLevel.info, callsite, args);
}

LogResult infof(string pattern, Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logfAt!(pattern, Args)(logger, LogLevel.info, callsite, args);
}

LogResult warning(Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logAt!Args(logger, LogLevel.warning, callsite, args);
}

LogResult warningf(string pattern, Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logfAt!(pattern, Args)(logger, LogLevel.warning, callsite, args);
}

LogResult error(Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logAt!Args(logger, LogLevel.error, callsite, args);
}

LogResult errorf(string pattern, Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logfAt!(pattern, Args)(logger, LogLevel.error, callsite, args);
}

LogResult critical(Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logAt!Args(logger, LogLevel.critical, callsite, args);
}

LogResult criticalf(string pattern, Args...)(
    ref Logger logger,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logfAt!(pattern, Args)(logger, LogLevel.critical, callsite, args);
}

bool flush(ref Logger logger)
{
    return logger.sink_.flush();
}
