module xtb.core.thread_logger;

nothrow @nogc:

import explicitLogger = xtb.core.logger;
import xtb.core.logger : Logger, LogLevel, LogResult, LogStatus;
import xtb.core.panic : require;
import xtb.core.thread_context : ThreadContext, currentThreadContext;

/// Temporarily installs a caller-owned logger in the current thread context.
/// The logger and its message buffer must outlive this scope.
struct ThreadLoggerScope
{
nothrow @nogc:

    private ThreadContext* context_;
    private Logger* installed_;
    private Logger* previous_;

    @disable this(this);

    static ThreadLoggerScope install(Logger* logger)
    {
        require(logger !is null, "cannot install a null thread logger");
        require(logger.valid, "cannot install an invalid thread logger");

        ThreadContext* context = currentThreadContext();
        require(context !is null, "logger installed without a thread context");

        ThreadLoggerScope result;
        result.context_ = context;
        result.installed_ = logger;
        result.previous_ = cast(Logger*) context.installedLogger;
        context.setInstalledLogger(cast(void*) logger);
        return result;
    }

    ~this()
    {
        if (context_ is null)
            return;

        require(
            currentThreadContext() is context_,
            "thread logger destroyed outside its thread context",
        );
        require(
            context_.installedLogger is cast(void*) installed_,
            "thread loggers destroyed out of order",
        );
        context_.setInstalledLogger(cast(void*) previous_);
        context_ = null;
        installed_ = null;
        previous_ = null;
    }
}

/// Returns the logger currently installed for this thread, or null when the
/// thread has no context or no logger has been installed in that context.
Logger* currentLogger()
{
    ThreadContext* context = currentThreadContext();
    return context is null ? null : cast(Logger*) context.installedLogger;
}

bool enabled(LogLevel level)
{
    Logger* logger = currentLogger();
    return logger !is null && explicitLogger.enabled(*logger, level);
}

LogResult log(Args...)(LogLevel level, auto ref Args args)
{
    Logger* logger = currentLogger();
    if (logger is null)
        return LogResult(LogStatus.invalidLogger, 0, 0);
    return explicitLogger.log(*logger, level, args);
}

LogResult logf(string pattern, Args...)(LogLevel level, auto ref Args args)
{
    Logger* logger = currentLogger();
    if (logger is null)
        return LogResult(LogStatus.invalidLogger, 0, 0);
    return explicitLogger.logf!pattern(*logger, level, args);
}

bool flushLogger()
{
    Logger* logger = currentLogger();
    return logger !is null && explicitLogger.flush(*logger);
}

version (unittest)
{
    private struct Capture
    {
        char[64] bytes;
        size_t length;
        size_t flushCount;
    }

    private bool captureSink(void* context, scope const explicitLogger.LogRecord* record)
    {
        Capture* capture = cast(Capture*) context;
        if (record.message.length > capture.bytes.length - capture.length)
            return false;
        foreach (index, value; record.message)
            capture.bytes[capture.length + index] = value;
        capture.length += record.message.length;
        return true;
    }

    private bool captureFlush(void* context)
    {
        Capture* capture = cast(Capture*) context;
        ++capture.flushCount;
        return true;
    }
}

unittest
{
    import xtb.core.print : Writer;
    import xtb.core.string : equal;
    import xtb.core.thread_context : ThreadContextScope;

    assert(currentLogger() is null);
    assert(!enabled(LogLevel.info));
    assert(log(LogLevel.info, "missing").status == LogStatus.invalidLogger);
    assert(!flushLogger());

    ThreadContextScope context = ThreadContextScope.acquire();
    assert(currentLogger() is null);

    struct FormatProbe
    {
    nothrow @nogc:

        size_t* calls;

        void formatTo(ref Writer writer)
        {
            ++*calls;
            writer.put("probe");
        }
    }

    Capture outerCapture;
    char[32] outerStorage;
    Logger outer = Logger.create(
        &captureSink,
        &outerCapture,
        outerStorage[],
        LogLevel.info,
        &captureFlush,
    );
    {
        ThreadLoggerScope outerScope = ThreadLoggerScope.install(&outer);
        assert(currentLogger() is &outer);
        assert(!enabled(LogLevel.debug_));
        assert(enabled(LogLevel.info));
        size_t formatCalls;
        FormatProbe probe = FormatProbe(&formatCalls);
        assert(log(LogLevel.debug_, probe).status == LogStatus.filtered);
        assert(formatCalls == 0);
        assert(logf!"value={}"(LogLevel.info, 17).delivered);
        assert(outerCapture.bytes[0 .. outerCapture.length].equal("value=17"));
        assert(flushLogger());
        assert(outerCapture.flushCount == 1);

        Capture nestedCapture;
        char[32] nestedStorage;
        Logger nested = Logger.create(
            &captureSink,
            &nestedCapture,
            nestedStorage[],
            LogLevel.trace,
        );
        {
            ThreadLoggerScope nestedScope = ThreadLoggerScope.install(&nested);
            assert(currentLogger() is &nested);
            assert(log(LogLevel.trace, "nested").delivered);
            assert(nestedCapture.bytes[0 .. nestedCapture.length].equal("nested"));
        }

        assert(currentLogger() is &outer);
        assert(log(LogLevel.warning, "!").delivered);
        assert(outerCapture.bytes[0 .. outerCapture.length].equal("value=17!"));
    }

    assert(currentLogger() is null);
}
