module xtb.core.logger;

nothrow @nogc:

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

struct LogRecord
{
    LogLevel level;
    String message;
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

alias LogSink = bool function(void* context, scope const LogRecord* record);
alias LogFlush = bool function(void* context);

struct Logger
{
nothrow @nogc:

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
    )
    {
        Logger result;
        result.sink_ = sink;
        result.flush_ = flush;
        result.context_ = context;
        result.messageBuffer_ = messageBuffer;
        result.minimumLevel_ = minimumLevel;
        return result;
    }

    bool valid() const pure @safe
    {
        return sink_ !is null;
    }

    LogLevel minimumLevel() const pure @safe
    {
        return minimumLevel_;
    }
}

private String levelName(LogLevel level) pure @safe
{
    final switch (level)
    {
        case LogLevel.trace:
            return "trace";
        case LogLevel.debug_:
            return "debug";
        case LogLevel.info:
            return "info";
        case LogLevel.warning:
            return "warning";
        case LogLevel.error:
            return "error";
        case LogLevel.critical:
            return "critical";
    }
}

private String levelColor(LogLevel level) pure @safe
{
    final switch (level)
    {
        case LogLevel.trace:
            return "\x1b[90m";
        case LogLevel.debug_:
            return "\x1b[94m";
        case LogLevel.info:
            return "\x1b[32m";
        case LogLevel.warning:
            return "\x1b[33m";
        case LogLevel.error:
            return "\x1b[91m";
        case LogLevel.critical:
            return "\x1b[1;91m";
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

void setSink(
    ref Logger logger,
    LogSink sink,
    void* context,
    LogFlush flush = null,
)
{
    logger.sink_ = sink;
    logger.context_ = context;
    logger.flush_ = flush;
}

private LogResult deliver(
    ref Logger logger,
    LogLevel level,
    BufferWriteResult formatted,
)
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
    return logger.valid && (logger.flush_ is null || logger.flush_(logger.context_));
}

private bool writeAll(FILE* file, String value)
{
    return value.length == 0 || fwrite(value.ptr, 1, value.length, file) == value.length;
}

private bool plainFileSink(void* context, scope const LogRecord* record)
{
    FILE* file = cast(FILE*) context;
    if (file is null)
        return false;
    lockFile(file);
    const accepted = writeAll(file, "[") &&
        writeAll(file, levelName(record.level)) && writeAll(file, "] ") &&
        writeAll(file, record.message) && writeAll(file, "\n");
    unlockFile(file);
    return accepted;
}

private bool ansiFileSink(void* context, scope const LogRecord* record)
{
    FILE* file = cast(FILE*) context;
    if (file is null)
        return false;
    lockFile(file);
    const accepted = writeAll(file, levelColor(record.level)) &&
        writeAll(file, "[") && writeAll(
            file, levelName(record.level)) &&
        writeAll(file, "]\x1b[0m ") && writeAll(file, record.message) &&
        writeAll(file, "\n");
    unlockFile(file);
    return accepted;
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

Logger fileLogger(
    FILE* file,
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
)
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
)
{
    return fileLogger(cast(FILE*) stderr, messageBuffer, minimumLevel, style);
}

Logger stdoutLogger(
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
)
{
    return fileLogger(cast(FILE*) stdout, messageBuffer, minimumLevel, style);
}

version (unittest)
{
    private struct Capture
    {
    nothrow @nogc:

        char[128] bytes;
        size_t length;
        LogLevel level;
    }

    private bool captureSink(void* context, scope const LogRecord* record)

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

    private bool rejectSink(void*, scope const LogRecord*)
    {
        return false;
    }

    private bool rejectFlush(void*)
    {
        return false;
    }

    private struct RecursiveCapture
    {
    nothrow @nogc:

        Logger* logger;
        LogStatus nestedStatus;
        char[16] outerMessage;
        size_t outerLength;
    }

    private bool recursiveSink(void* context, scope const LogRecord* record)

    {
        RecursiveCapture* capture = cast(RecursiveCapture*) context;
        capture.nestedStatus = (*capture.logger).log(LogLevel.error, "nested").status;
        capture.outerLength = record.message.length;
        foreach (index, character; record.message)
            capture.outerMessage[index] = character;
        return true;
    }
}

unittest
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

    logger.setMinimumLevel(LogLevel.trace);
    capture.length = 0;
    assert(logger.trace("trace").delivered && capture.level == LogLevel.trace);
    assert(logger.tracef!"{}"("tracef").delivered &&
            capture.level == LogLevel.trace);
    assert(logger.debug_("debug").delivered && capture.level == LogLevel.debug_);
    assert(logger.debugf!"{}"("debugf").delivered &&
            capture.level == LogLevel.debug_);
    assert(logger.info("info").delivered && capture.level == LogLevel.info);
    assert(logger.infof!"{}"("infof").delivered && capture.level == LogLevel.info);
    assert(logger.warning("warning").delivered && capture.level == LogLevel.warning);
    assert(logger.warningf!"{}"("warningf").delivered &&
            capture.level == LogLevel.warning);
    assert(logger.error("error").delivered && capture.level == LogLevel.error);
    assert(logger.errorf!"{}"("errorf").delivered && capture.level == LogLevel.error);
    assert(logger.critical("critical").delivered &&
            capture.level == LogLevel.critical);
    assert(logger.criticalf!"{}"("criticalf").delivered &&
            capture.level == LogLevel.critical);

    Logger invalid;
    assert(invalid.log(LogLevel.info, "ignored").status == LogStatus.invalidLogger);
    assert(!invalid.flush());

    logger.setSink(&rejectSink, null, &rejectFlush);
    assert(logger.log(LogLevel.error, "rejected").status == LogStatus.sinkFailed);
    assert(!logger.flush());

    RecursiveCapture recursive;
    Logger recursiveLogger = Logger.create(
        &recursiveSink,
        &recursive,
        messageBuffer[],
    );
    recursive.logger = &recursiveLogger;
    assert(recursiveLogger.log(LogLevel.error, "outer").status == LogStatus.delivered);
    assert(recursive.nestedStatus == LogStatus.recursive);
    assert(recursive.outerMessage[0 .. recursive.outerLength].equal("outer"));
}
