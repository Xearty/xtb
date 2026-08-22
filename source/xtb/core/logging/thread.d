module xtb.core.logging.thread;

nothrow @nogc:

import explicitLogger = xtb.core.logging.logger;
import explicitSink = xtb.core.logging.sink;
import xtb.core.logging.level : LogLevel;
import xtb.core.logging.logger : Logger;
import xtb.core.logging.result : LogResult, LogStatus;
import xtb.core.logging.sink : LogSourceLocation;

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

LogResult log(Args...)(
    LogLevel level,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logAt!Args(level, callsite, args);
}

LogResult logf(string pattern, Args...)(
    LogLevel level,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logfAt!(pattern, Args)(level, callsite, args);
}

private LogResult logAt(Args...)(
    LogLevel level,
    LogSourceLocation callsite,
    auto ref Args args,
)
{
    Logger* logger = currentLogger();
    if (logger is null)
        return LogResult(LogStatus.invalidLogger, 0, 0);
    return explicitLogger.logAt!Args(*logger, level, callsite, args);
}

private LogResult logfAt(string pattern, Args...)(
    LogLevel level,
    LogSourceLocation callsite,
    auto ref Args args,
)
{
    Logger* logger = currentLogger();
    if (logger is null)
        return LogResult(LogStatus.invalidLogger, 0, 0);
    return explicitLogger.logfAt!(pattern, Args)(*logger, level, callsite, args);
}

LogResult trace(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logAt!Args(LogLevel.trace, callsite, args);
}

LogResult tracef(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logfAt!(pattern, Args)(LogLevel.trace, callsite, args);
}

LogResult debug_(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logAt!Args(LogLevel.debug_, callsite, args);
}

LogResult debugf(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logfAt!(pattern, Args)(LogLevel.debug_, callsite, args);
}

LogResult info(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logAt!Args(LogLevel.info, callsite, args);
}

LogResult infof(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logfAt!(pattern, Args)(LogLevel.info, callsite, args);
}

LogResult warning(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logAt!Args(LogLevel.warning, callsite, args);
}

LogResult warningf(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logfAt!(pattern, Args)(LogLevel.warning, callsite, args);
}

LogResult error(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logAt!Args(LogLevel.error, callsite, args);
}

LogResult errorf(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logfAt!(pattern, Args)(LogLevel.error, callsite, args);
}

LogResult critical(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logAt!Args(LogLevel.critical, callsite, args);
}

LogResult criticalf(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
) if (!StartsWithLogger!Args)
{
    return logfAt!(pattern, Args)(LogLevel.critical, callsite, args);
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
        scope const explicitSink.LogSinkEvent* event,
    )
    {
        Capture* capture = cast(Capture*) context;
        if (event.kind == explicitSink.LogSinkEventKind.messageChunk)
        {
            if (event.bytes.length > capture.bytes.length - capture.length)
                return false;
            foreach (index, value; event.bytes)
                capture.bytes[capture.length + index] = value;
            capture.length += event.bytes.length;
        }
        else if (event.kind == explicitSink.LogSinkEventKind.text &&
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

    private struct SourceCapture
    {
    nothrow @nogc:

        char[128] functionName;
        size_t functionNameLength;
        size_t line;

        String functionText() const return @trusted
        {
            return functionName[0 .. functionNameLength];
        }
    }

    private bool acceptAllSink(
        void*,
        scope const explicitSink.LogSinkEvent* event,
    )
    {
        return event !is null;
    }

    private explicitSink.LogRecordRef captureSourceResolver(
        void* context,
        scope return const ref explicitSink.LogRecordInfo info,
        scope return const(explicitSink.LogSourceLocation)* callsite,
    )
    {
        SourceCapture* capture = cast(SourceCapture*) context;
        if (capture is null || callsite is null ||
            callsite.functionName.length > capture.functionName.length)
            return explicitSink.LogRecordRef.init;

        capture.functionNameLength = callsite.functionName.length;
        foreach (index, value; callsite.functionName)
            capture.functionName[index] = value;
        capture.line = callsite.line;

        auto child = explicitSink.LogSinkRef.create(&acceptAllSink, null);
        return child.beginRecord(info, callsite);
    }
}

unittest
{
    import xtb.core.writer : Writer;
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

        // TLS helpers preserve the application caller through both the thread
        // wrapper and the explicit logger wrapper when callsites are enabled.
        SourceCapture sourceCapture;
        char[32] sourceStorage;
        Logger sourceLogger = Logger.create(
            explicitSink.LogSinkRef.create(&captureSourceResolver, &sourceCapture),
            sourceStorage[],
            LogLevel.trace,
        );
        explicitLogger.setCallsitesEnabled(sourceLogger, true);
        {
            ThreadLoggerScope sourceScope = ThreadLoggerScope.install(&sourceLogger);
            const sourceFunction = cast(String) __FUNCTION__;

            const directLine = __LINE__ + 1;
            assert(log(LogLevel.info, "direct").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(sourceCapture.line == directLine);

            assert(logf!"{}"(LogLevel.info, "formatted").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(trace("trace").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(tracef!"{}"("tracef").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(debug_("debug").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(debugf!"{}"("debugf").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(info("info").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(infof!"{}"("infof").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(warning("warning").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(warningf!"{}"("warningf").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(error("error").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(errorf!"{}"("errorf").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(critical("critical").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
            assert(criticalf!"{}"("criticalf").delivered);
            assert(sourceCapture.functionText.equal(sourceFunction));
        }
        assert(currentLogger() is &outer);

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
