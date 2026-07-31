module xtb.core.logger;

import xtb.core.print : Sink, Writer;
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

struct Logger
{
    Sink sink;
    void* context;
    LogLevel minimumLevel = LogLevel.info;

    bool valid() const pure nothrow @safe @nogc
    {
        return sink !is null;
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

bool enabled(Logger logger, LogLevel level)
    pure nothrow @safe @nogc
{
    return logger.valid && level >= logger.minimumLevel;
}

void log(Args...)(
    Logger logger,
    LogLevel level,
    auto ref Args args,
) nothrow @nogc
{
    if (!logger.enabled(level))
        return;

    Writer writer = Writer.fromSink(logger.sink, logger.context);
    writer.put('[');
    writer.put(levelName(level));
    writer.put("] ");
    static foreach (i; 0 .. Args.length)
        writer.value(args[i]);
    writer.put('\n');
    writer.finish();
}

version (unittest)
{
    private struct Capture
    {
        char[64] bytes;
        size_t length;
    }

    private size_t captureSink(void* context, scope String bytes) nothrow @nogc
    {
        Capture* capture = cast(Capture*) context;
        const available = capture.bytes.length - capture.length;
        const amount = bytes.length < available ? bytes.length : available;
        foreach (i; 0 .. amount)
            capture.bytes[capture.length + i] = bytes[i];
        capture.length += amount;
        return amount;
    }
}

nothrow @nogc unittest
{
    import xtb.core.string : equal;

    Capture capture;
    Logger logger = Logger(&captureSink, &capture, LogLevel.debug_);
    logger.log(LogLevel.trace, "hidden");
    assert(capture.length == 0);
    logger.log(LogLevel.info, "value=", 7);
    assert(capture.bytes[0 .. capture.length].equal("[info] value=7\n"));
}
