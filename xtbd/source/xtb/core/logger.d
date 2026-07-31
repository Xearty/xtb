module xtb.core.logger;

import core.stdc.stdio : FILE, fflush, fwrite, stderr, stdout;
import xtb.core.print : BufferWriteResult, formatBuffer, writeBuffer;
import xtb.core.string : String;

enum LogLevel : ubyte
{
    trace,
    debug_,
    info,
    warning,
    error,
    fatal,
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

struct LogRecord
{
    LogLevel level;
    String message;
}

struct LogResult
{
    LogStatus status;
    size_t written;
    size_t required;

    bool delivered() const pure nothrow @safe @nogc
    {
        return status == LogStatus.delivered || status == LogStatus.truncated;
    }
}

alias LogSink = bool function(void* context, scope const LogRecord* record)
    nothrow @nogc;
alias LogFlush = bool function(void* context) nothrow @nogc;

struct Logger
{
    private LogSink sink_;
    private LogFlush flush_;
    private void* context_;
    private char[] messageBuffer_;
    private LogLevel minimumLevel_;
    private bool delivering_;

    @disable this(this);

    static Logger create(
        LogSink sink,
        void* context,
        return scope char[] messageBuffer,
        LogLevel minimumLevel = LogLevel.info,
        LogFlush flush = null,
    ) nothrow @nogc
    {
        Logger result;
        result.sink_ = sink;
        result.flush_ = flush;
        result.context_ = context;
        result.messageBuffer_ = messageBuffer;
        result.minimumLevel_ = minimumLevel;
        return result;
    }

    bool valid() const pure nothrow @safe @nogc
    {
        return sink_ !is null;
    }

    LogLevel minimumLevel() const pure nothrow @safe @nogc
    {
        return minimumLevel_;
    }
}

private String levelName(LogLevel level) pure nothrow @safe @nogc
{
    final switch (level)
    {
        case LogLevel.trace: return "trace";
        case LogLevel.debug_: return "debug";
        case LogLevel.info: return "info";
        case LogLevel.warning: return "warning";
        case LogLevel.error: return "error";
        case LogLevel.fatal: return "fatal";
    }
}

private String levelColor(LogLevel level) pure nothrow @safe @nogc
{
    final switch (level)
    {
        case LogLevel.trace: return "\x1b[90m";
        case LogLevel.debug_: return "\x1b[94m";
        case LogLevel.info: return "\x1b[32m";
        case LogLevel.warning: return "\x1b[33m";
        case LogLevel.error: return "\x1b[91m";
        case LogLevel.fatal: return "\x1b[1;91m";
    }
}

bool enabled(ref const Logger logger, LogLevel level)
    pure nothrow @safe @nogc
{
    return logger.valid && level >= logger.minimumLevel_;
}

void setMinimumLevel(ref Logger logger, LogLevel level) nothrow @nogc
{
    logger.minimumLevel_ = level;
}

void setSink(
    ref Logger logger,
    LogSink sink,
    void* context,
    LogFlush flush = null,
) nothrow @nogc
{
    logger.sink_ = sink;
    logger.context_ = context;
    logger.flush_ = flush;
}

private LogResult deliver(
    ref Logger logger,
    LogLevel level,
    BufferWriteResult formatted,
) nothrow @nogc
{
    if (logger.delivering_)
        return LogResult(LogStatus.recursive, 0, formatted.required);
    logger.delivering_ = true;
    LogRecord record = LogRecord(
        level,
        logger.messageBuffer_[0 .. formatted.written],
    );
    const accepted = logger.sink_(logger.context_, &record);
    logger.delivering_ = false;
    if (!accepted)
        return LogResult(LogStatus.sinkFailed, formatted.written, formatted.required);
    return LogResult(
        formatted.truncated ? LogStatus.truncated : LogStatus.delivered,
        formatted.written,
        formatted.required,
    );
}

LogResult log(Args...)(
    ref Logger logger,
    LogLevel level,
    auto ref Args args,
) nothrow @nogc
{
    if (!logger.valid)
        return LogResult(LogStatus.invalidLogger, 0, 0);
    if (level < logger.minimumLevel_)
        return LogResult(LogStatus.filtered, 0, 0);
    const formatted = writeBuffer(logger.messageBuffer_, args);
    return logger.deliver(level, formatted);
}

LogResult logf(string pattern, Args...)(
    ref Logger logger,
    LogLevel level,
    auto ref Args args,
) nothrow @nogc
{
    if (!logger.valid)
        return LogResult(LogStatus.invalidLogger, 0, 0);
    if (level < logger.minimumLevel_)
        return LogResult(LogStatus.filtered, 0, 0);
    const formatted = formatBuffer!pattern(logger.messageBuffer_, args);
    return logger.deliver(level, formatted);
}

bool flush(ref Logger logger) nothrow @nogc
{
    return logger.valid && (logger.flush_ is null || logger.flush_(logger.context_));
}

private bool writeAll(FILE* file, String value) nothrow @nogc
{
    return value.length == 0 || fwrite(value.ptr, 1, value.length, file) == value.length;
}

private bool plainFileSink(void* context, scope const LogRecord* record)
    nothrow @nogc
{
    FILE* file = cast(FILE*) context;
    return file !is null && writeAll(file, "[") &&
        writeAll(file, levelName(record.level)) && writeAll(file, "] ") &&
        writeAll(file, record.message) && writeAll(file, "\n");
}

private bool ansiFileSink(void* context, scope const LogRecord* record)
    nothrow @nogc
{
    FILE* file = cast(FILE*) context;
    return file !is null && writeAll(file, levelColor(record.level)) &&
        writeAll(file, "[") && writeAll(file, levelName(record.level)) &&
        writeAll(file, "]\x1b[0m ") && writeAll(file, record.message) &&
        writeAll(file, "\n");
}

private bool fileFlush(void* context) nothrow @nogc
{
    FILE* file = cast(FILE*) context;
    return file !is null && fflush(file) == 0;
}

Logger fileLogger(
    FILE* file,
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
) nothrow @nogc
{
    return Logger.create(
        style == LogStyle.ansi ? &ansiFileSink : &plainFileSink,
        cast(void*) file,
        messageBuffer,
        minimumLevel,
        &fileFlush,
    );
}

Logger stderrLogger(
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
) nothrow @nogc
{
    return fileLogger(cast(FILE*) stderr, messageBuffer, minimumLevel, style);
}

Logger stdoutLogger(
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
) nothrow @nogc
{
    return fileLogger(cast(FILE*) stdout, messageBuffer, minimumLevel, style);
}

version (unittest)
{
    private struct Capture
    {
        char[64] bytes;
        size_t length;
        LogLevel level;
    }

    private bool captureSink(void* context, scope const LogRecord* record)
        nothrow @nogc
    {
        Capture* capture = cast(Capture*) context;
        capture.level = record.level;
        const available = capture.bytes.length - capture.length;
        const amount = record.message.length < available
            ? record.message.length : available;
        foreach (i; 0 .. amount)
            capture.bytes[capture.length + i] = record.message[i];
        capture.length += amount;
        return amount == record.message.length;
    }
}

nothrow @nogc unittest
{
    import xtb.core.string : equal;

    Capture capture;
    char[16] messageBuffer;
    Logger logger = Logger.create(
        &captureSink,
        &capture,
        messageBuffer[],
        LogLevel.debug_,
    );
    assert(logger.log(LogLevel.trace, "hidden").status == LogStatus.filtered);
    LogResult result = logger.logf!"value={}"(LogLevel.info, 7);
    assert(result.status == LogStatus.delivered);
    assert(capture.level == LogLevel.info);
    assert(capture.bytes[0 .. capture.length].equal("value=7"));

    capture.length = 0;
    result = logger.log(LogLevel.warning, "message longer than buffer");
    assert(result.status == LogStatus.truncated && result.required > result.written);
    assert(logger.flush());
}
