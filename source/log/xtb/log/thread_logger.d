module xtb.log.thread_logger;

nothrow @nogc:

import core.attribute;

import xtb.log.level;
import xtb.log.logger;
import xtb.log.result;
import xtb.log.sink;
import xtb.panic;
import xtb.thread_context;

private Logger* tls_logger;

private template starts_with_logger(Args...)
{
    static if (Args.length == 0)
    {
        enum starts_with_logger = false;
    }
    else
    {
        enum starts_with_logger = is(typeof(cast() Args[0].init) == Logger);
    }
}

/// Temporarily installs a caller-owned logger in the current thread context.
/// The logger and its borrowed state must outlive this scope. Nested thread
/// logger scopes must be destroyed in reverse installation order and before the
/// owning thread-context scope ends.
@mustuse struct ThreadLoggerScope
{
nothrow @nogc:

    /// Thread-context attachment owned by this scope. Null denotes an inactive scope.
    ThreadContext* context;
    /// Logger installed by this scope and borrowed for its lifetime.
    Logger* installed;
    /// Previously installed logger restored when this scope ends.
    Logger* previous;

    @disable this(this);

    /// Installs `logger` until the returned scope is destroyed. The enclosing
    /// thread context and any previous installation must remain active for that
    /// complete lifetime.
    static ThreadLoggerScope install(return scope Logger* logger) @system
    {
        require(logger !is null, "cannot install a null thread logger");
        require(logger.valid, "cannot install an invalid thread logger");

        ThreadContext* context = attach_thread_context();

        ThreadLoggerScope result;
        result.context = context;
        result.installed = logger;
        result.previous = tls_logger;
        tls_logger = logger;
        return result;
    }

    ~this()
    {
        if (this.context is null) return;

        require(
            current_thread_context() is this.context,
            "thread logger destroyed outside its thread context",
        );
        require(
            tls_logger is this.installed,
            "thread loggers destroyed out of order",
        );

        tls_logger = this.previous;
        detach_thread_context(this.context);
        this.context = null;
        this.installed = null;
        this.previous = null;
    }
}

/// Returns the logger currently installed for this thread, or null when the
/// thread has no context or no logger has been installed in that context.
/// The returned pointer is borrowed and remains valid only while its installing
/// `ThreadLoggerScope` is active. That lifetime is held in thread-local state and
/// cannot be expressed in the return type, so callers must not retain the pointer.
Logger* current_logger() @system
{
    return current_thread_context() is null ? null : tls_logger;
}

bool enabled(LogLevel level)
{
    Logger* logger = current_logger();
    return logger !is null && (*logger).enabled(level);
}

LogResult log(Args...)(
    LogLevel level,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return log_at!Args(level, callsite, args);
}

LogResult logf(string pattern, Args...)(
    LogLevel level,
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
{
    return logf_at!(pattern, Args)(level, callsite, args);
}

private LogResult log_at(Args...)(LogLevel level, LogSourceLocation callsite, auto ref Args args)
{
    Logger* logger = current_logger();
    if (logger is null) return LogResult(LogStatus.invalid_logger, 0, 0);

    return (*logger).log_at!Args(level, callsite, args);
}

private LogResult logf_at(string pattern, Args...)(
    LogLevel level,
    LogSourceLocation callsite,
    auto ref Args args,
)
{
    Logger* logger = current_logger();
    if (logger is null) return LogResult(LogStatus.invalid_logger, 0, 0);

    return (*logger).logf_at!(pattern, Args)(level, callsite, args);
}

LogResult trace(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return log_at!Args(LogLevel.trace, callsite, args);
}

LogResult tracef(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return logf_at!(pattern, Args)(LogLevel.trace, callsite, args);
}

LogResult debug_(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return log_at!Args(LogLevel.debug_, callsite, args);
}

LogResult debugf(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return logf_at!(pattern, Args)(LogLevel.debug_, callsite, args);
}

LogResult info(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return log_at!Args(LogLevel.info, callsite, args);
}

LogResult infof(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return logf_at!(pattern, Args)(LogLevel.info, callsite, args);
}

LogResult warning(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return log_at!Args(LogLevel.warning, callsite, args);
}

LogResult warningf(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return logf_at!(pattern, Args)(LogLevel.warning, callsite, args);
}

LogResult error(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return log_at!Args(LogLevel.error, callsite, args);
}

LogResult errorf(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return logf_at!(pattern, Args)(LogLevel.error, callsite, args);
}

LogResult fatal(Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return log_at!Args(LogLevel.fatal, callsite, args);
}

LogResult fatalf(string pattern, Args...)(
    auto ref Args args,
    LogSourceLocation callsite = LogSourceLocation(__FUNCTION__, __LINE__),
)
if (!starts_with_logger!Args)
{
    return logf_at!(pattern, Args)(LogLevel.fatal, callsite, args);
}

bool try_flush_logger()
{
    Logger* logger = current_logger();
    return logger !is null && (*logger).try_flush();
}

version (unittest)
{
    import xtb.fmt.writer;
    import xtb.string;
    import xtb.types;

    private struct Capture
    {
    nothrow @nogc:

        char[128] bytes;
        usize length;
        char[16] label;
        usize label_length;
        usize flush_count;

        String label_text() const return @safe
        {
            return this.label[0 .. this.label_length];
        }
    }

    private bool try_capture_sink(void* context, scope const LogSinkEvent* event) @system
    {
        auto capture = cast(Capture*) context;
        if (event.kind == LogSinkEventKind.message_chunk)
        {
            if (event.bytes.length > capture.bytes.length - capture.length) return false;

            foreach (index, value; event.bytes)
                capture.bytes[capture.length + index] = value;

            capture.length += event.bytes.length;
        }
        else if (event.kind == LogSinkEventKind.text
            && event.bytes.length >= 2
            && event.bytes[0] == '[')
        {
            if (event.bytes.length > capture.label.length) return false;

            capture.label_length = event.bytes.length;
            foreach (index, value; event.bytes)
                capture.label[index] = value;
        }
        return true;
    }

    private bool try_capture_flush(void* context) @system
    {
        auto capture = cast(Capture*) context;
        ++capture.flush_count;
        return true;
    }

    private struct SourceCapture
    {
    nothrow @nogc:

        char[128] function_name;
        usize function_name_length;
        usize line;

        String function_text() const return @safe
        {
            return this.function_name[0 .. this.function_name_length];
        }
    }

    private bool try_accept_all_sink(void*, scope const LogSinkEvent* event)
    {
        return event !is null;
    }

    private LogRecordRef capture_source_resolver(
        void* context,
        scope return const ref LogRecordInfo info,
        scope return const(LogSourceLocation)* callsite,
    ) @system
    {
        auto capture = cast(SourceCapture*) context;
        if (capture is null
            || callsite is null
            || callsite.function_name.length > capture.function_name.length)
        {
            return LogRecordRef.init;
        }

        capture.function_name_length = callsite.function_name.length;
        foreach (index, value; callsite.function_name)
            capture.function_name[index] = value;

        capture.line = callsite.line;

        auto child = LogSinkRef.create(&try_accept_all_sink, null);
        return child.begin_record(info, callsite);
    }
}

unittest
{
    assert(current_logger() is null);
    assert(!enabled(LogLevel.info));
    assert(log(LogLevel.info, "missing").status == LogStatus.invalid_logger);
    assert(!try_flush_logger());

    auto context = ThreadContextScope.acquire();
    assert(current_logger() is null);

    struct FormatProbe
    {
    nothrow @nogc:

        usize* calls;

        void format_to(ref Writer writer)
        {
            ++*this.calls;
            writer.put("probe");
        }
    }

    Capture outer_capture;
    char[32] outer_storage;
    auto outer = Logger.create(
        &try_capture_sink,
        &outer_capture,
        outer_storage[],
        LogLevel.info,
        &try_capture_flush,
    );
    {
        auto outer_scope = ThreadLoggerScope.install(&outer);
        assert(current_logger() is &outer);
        assert(!enabled(LogLevel.debug_));
        assert(enabled(LogLevel.info));
        usize format_calls;
        auto probe = FormatProbe(&format_calls);
        assert(log(LogLevel.debug_, probe).status == LogStatus.filtered);
        assert(format_calls == 0);
        assert(logf!"value={}"(LogLevel.info, 17).delivered);
        assert(outer_capture.bytes[0 .. outer_capture.length].equal("value=17"));
        assert(try_flush_logger());
        assert(outer_capture.flush_count == 1);

        outer.minimum_level = LogLevel.trace;
        outer_capture.length = 0;
        assert(trace("trace").delivered && outer_capture.label_text.equal("[trace]"));
        assert(tracef!"{}"("tracef").delivered && outer_capture.label_text.equal("[trace]"));
        assert(debug_("debug").delivered && outer_capture.label_text.equal("[debug]"));
        assert(debugf!"{}"("debugf").delivered && outer_capture.label_text.equal("[debug]"));
        assert(info("info").delivered && outer_capture.label_text.equal("[info]"));
        assert(infof!"{}"("infof").delivered && outer_capture.label_text.equal("[info]"));
        assert(warning("warning").delivered && outer_capture.label_text.equal("[warning]"));
        assert(warningf!"{}"("warningf").delivered && outer_capture.label_text.equal("[warning]"));
        assert(error("error").delivered && outer_capture.label_text.equal("[error]"));
        assert(errorf!"{}"("errorf").delivered && outer_capture.label_text.equal("[error]"));
        assert(fatal("fatal").delivered && outer_capture.label_text.equal("[fatal]"));
        assert(fatalf!"{}"("fatalf").delivered && outer_capture.label_text.equal("[fatal]"));
        outer_capture.length = 0;

        // TLS helpers preserve the application caller through both the thread
        // wrapper and the explicit logger wrapper when callsites are enabled.
        SourceCapture source_capture;
        char[32] source_storage;
        auto source_logger = Logger.create(
            LogSinkRef.create(&capture_source_resolver, &source_capture),
            source_storage[],
            LogLevel.trace,
        );
        source_logger.callsites_enabled = true;
        {
            auto source_scope = ThreadLoggerScope.install(&source_logger);
            const source_function = cast(String) __FUNCTION__;

            const usize direct_line = __LINE__ + 1;
            assert(log(LogLevel.info, "direct").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(source_capture.line == direct_line);

            assert(logf!"{}"(LogLevel.info, "formatted").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(trace("trace").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(tracef!"{}"("tracef").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(debug_("debug").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(debugf!"{}"("debugf").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(info("info").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(infof!"{}"("infof").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(warning("warning").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(warningf!"{}"("warningf").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(error("error").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(errorf!"{}"("errorf").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(fatal("fatal").delivered);
            assert(source_capture.function_text.equal(source_function));
            assert(fatalf!"{}"("fatalf").delivered);
            assert(source_capture.function_text.equal(source_function));
        }
        assert(current_logger() is &outer);

        Capture nested_capture;
        char[32] nested_storage;
        auto nested = Logger.create(
            &try_capture_sink,
            &nested_capture,
            nested_storage[],
            LogLevel.trace,
        );
        {
            auto nested_scope = ThreadLoggerScope.install(&nested);
            assert(current_logger() is &nested);
            assert(log(LogLevel.trace, "nested").delivered);
            assert(nested_capture.bytes[0 .. nested_capture.length].equal("nested"));
        }

        assert(current_logger() is &outer);
        assert(log(LogLevel.warning, "!").delivered);
        assert(outer_capture.bytes[0 .. outer_capture.length].equal("!"));
    }

    assert(current_logger() is null);
}
