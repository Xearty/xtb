module xtb.core.thread_logger;

nothrow @nogc:

import explicitLogger = xtb.core.logger;
import xtb.core.logger : Logger, LogLevel, LogResult, LogStatus;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.core.thread_context : ThreadContext, currentThreadContext;

private template StartsWithLogger(Args...)
{
    static if (Args.length == 0)
        enum StartsWithLogger = false;
    else
        enum StartsWithLogger = is(typeof(cast() Args[0].init) == Logger);
}

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
        version (XTB_Checked)
        {
            require(logger !is null, "cannot install a null thread logger");
            require(logger.valid, "cannot install an invalid thread logger");
        }

        ThreadContext* context = currentThreadContext();
        version (XTB_Checked)
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

        version (XTB_Checked)
        {
            require(
                currentThreadContext() is context_,
                "thread logger destroyed outside its thread context",
            );
            require(
                context_.installedLogger is cast(void*) installed_,
                "thread loggers destroyed out of order",
            );
        }
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

LogResult trace(Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return log(LogLevel.trace, args);
}

LogResult tracef(string pattern, Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return logf!pattern(LogLevel.trace, args);
}

LogResult debug_(Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return log(LogLevel.debug_, args);
}

LogResult debugf(string pattern, Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return logf!pattern(LogLevel.debug_, args);
}

LogResult info(Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return log(LogLevel.info, args);
}

LogResult infof(string pattern, Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return logf!pattern(LogLevel.info, args);
}

LogResult warning(Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return log(LogLevel.warning, args);
}

LogResult warningf(string pattern, Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return logf!pattern(LogLevel.warning, args);
}

LogResult error(Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return log(LogLevel.error, args);
}

LogResult errorf(string pattern, Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return logf!pattern(LogLevel.error, args);
}

LogResult critical(Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return log(LogLevel.critical, args);
}

LogResult criticalf(string pattern, Args...)(auto ref Args args) if (!StartsWithLogger!Args)
{
    return logf!pattern(LogLevel.critical, args);
}

bool flushLogger()
{
    Logger* logger = currentLogger();
    return logger !is null && explicitLogger.flush(*logger);
}

version (unittest)
{
    import xtb.core.string : String;

    private struct Capture
    {
    nothrow @nogc:

        char[128] bytes;
        size_t length;
        char[16] label;
        size_t labelLength;
        size_t flushCount;

        String labelText() const return @trusted
        {
            return label[0 .. labelLength];
        }
    }

    private bool captureSink(
        void* context,
        scope const explicitLogger.LogSinkEvent* event,
    )
    {
        Capture* capture = cast(Capture*) context;
        if (event.kind == explicitLogger.LogSinkEventKind.messageChunk)
        {
            if (event.bytes.length > capture.bytes.length - capture.length)
                return false;
            foreach (index, value; event.bytes)
                capture.bytes[capture.length + index] = value;
            capture.length += event.bytes.length;
        }
        else if (event.kind == explicitLogger.LogSinkEventKind.text &&
            event.bytes.length >= 2 && event.bytes[0] == '[')
        {
            if (event.bytes.length > capture.label.length)
                return false;
            capture.labelLength = event.bytes.length;
            foreach (index, value; event.bytes)
                capture.label[index] = value;
        }
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
    import xtb.core.string;
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

        explicitLogger.setMinimumLevel(outer, LogLevel.trace);
        outerCapture.length = 0;
        assert(trace("trace").delivered && outerCapture.labelText.equal("[trace]"));
        assert(tracef!"{}"("tracef").delivered &&
                outerCapture.labelText.equal("[trace]"));
        assert(debug_("debug").delivered && outerCapture.labelText.equal("[debug]"));
        assert(debugf!"{}"("debugf").delivered &&
                outerCapture.labelText.equal("[debug]"));
        assert(info("info").delivered && outerCapture.labelText.equal("[info]"));
        assert(infof!"{}"("infof").delivered &&
                outerCapture.labelText.equal("[info]"));
        assert(warning("warning").delivered &&
                outerCapture.labelText.equal("[warning]"));
        assert(warningf!"{}"("warningf").delivered &&
                outerCapture.labelText.equal("[warning]"));
        assert(error("error").delivered && outerCapture.labelText.equal("[error]"));
        assert(errorf!"{}"("errorf").delivered &&
                outerCapture.labelText.equal("[error]"));
        assert(critical("critical").delivered &&
                outerCapture.labelText.equal("[critical]"));
        assert(criticalf!"{}"("criticalf").delivered &&
                outerCapture.labelText.equal("[critical]"));
        outerCapture.length = 0;

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
        assert(outerCapture.bytes[0 .. outerCapture.length].equal("!"));
    }

    assert(currentLogger() is null);
}
