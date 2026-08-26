module xtb.log.timestamp_prefix;

nothrow @nogc:

import xtb.ansi : AnsiColor, AnsiStyle;
import xtb.log.prefix_sink : LogPrefixRef, LogPrefixWriter;

version (unittest)
{
    import xtb.log.level : LogLevel;
    import xtb.log.sink : LogRecordInfo, LogRecordRef, LogSinkEvent, LogSinkEventKind;
}
import xtb.string : String;
import xtb.types : i64;
import xtb.os.error : OsError;
import xtb.os.time : wallClockNanoseconds;

enum LogTimestampZone : ubyte
{
    local,
    utc,
}

/// Formatting and presentation policy for one timestamp prefix.
///
/// `separator` is borrowed by `TimestampLogPrefix` and must outlive every use
/// of a prefix reference created from it.
struct LogTimestampOptions
{
nothrow @nogc:

    LogTimestampZone zone;
    bool milliseconds;
    AnsiStyle style;
    String separator;

    static LogTimestampOptions defaults()
    @safe
    {
        LogTimestampOptions result;
        result.zone = LogTimestampZone.local;
        result.style = AnsiStyle.foreground(AnsiColor.brightBlack).dim;
        result.separator = " ";
        return result;
    }
}

private alias TimestampClock = OsError function(void* context, i64* output);

/// Non-owning wall-clock timestamp prefix provider.
///
/// The provider formats each timestamp into fixed stack storage and emits it
/// synchronously through `LogPrefixWriter`. `prefixRef()` borrows this value,
/// so it must remain at a stable address while the returned reference is used.
struct TimestampLogPrefix
{
nothrow @nogc:

    private LogTimestampOptions options_;
    private TimestampClock clock_;
    private void* clockContext_;

    @disable this(this);

    static TimestampLogPrefix create(
        LogTimestampOptions options = LogTimestampOptions.defaults(),
    )
    {
        return createWithClock(options, &systemTimestampClock, null);
    }

    LogPrefixRef prefixRef() return @trusted
    {
        return LogPrefixRef.create(&timestampPrefixCallback, cast(void*)&this);
    }

    private static TimestampLogPrefix createWithClock(
        LogTimestampOptions options,
        TimestampClock clock,
        void* context,
    )
    {
        TimestampLogPrefix result;
        result.options_ = options;
        result.clock_ = clock;
        result.clockContext_ = context;
        return result;
    }
}

private OsError systemTimestampClock(void*, i64* output) @system
{
    return wallClockNanoseconds(output);
}

private bool timestampPrefixCallback(void* context, LogPrefixWriter* output)
{
    TimestampLogPrefix* timestamp = cast(TimestampLogPrefix*) context;
    if (timestamp is null || output is null || timestamp.clock_ is null)
        return false;

    i64 nanoseconds;
    if (timestamp.clock_(timestamp.clockContext_, &nanoseconds).failed)
        return false;

    char[32] storage;
    const formatted = formatTimestamp(
        nanoseconds,
        timestamp.options_.zone,
        timestamp.options_.milliseconds,
        storage[],
    );
    if (formatted.length == 0)
        return false;
    if (!output.write(formatted, timestamp.options_.style))
        return false;
    return timestamp.options_.separator.length == 0 ||
        output.write(timestamp.options_.separator);
}

private String formatTimestamp(
    i64 nanoseconds,
    LogTimestampZone zone,
    bool milliseconds,
    return scope char[] output,
) @system
{
    enum i64 nanosecondsPerSecond = 1_000_000_000L;
    i64 seconds = nanoseconds / nanosecondsPerSecond;
    i64 remainder = nanoseconds % nanosecondsPerSecond;
    if (remainder < 0)
    {
        --seconds;
        remainder += nanosecondsPerSecond;
    }

    version (Posix)
    {
        import core.sys.posix.stdc.time : time_t, tm;
        import core.sys.posix.time : gmtime_r, localtime_r;

        const nativeSeconds = cast(time_t) seconds;
        if (cast(i64) nativeSeconds != seconds)
            return null;

        tm calendar;
        tm* converted = zone == LogTimestampZone.utc
            ? gmtime_r(&nativeSeconds, &calendar) : localtime_r(&nativeSeconds, &calendar);
        if (converted is null)
            return null;

        const year = calendar.tm_year + 1900;
        if (year < 0 || year > 9999)
            return null;
        const required = (zone == LogTimestampZone.utc ? 20u : 19u) +
            (milliseconds ? 4u : 0u);
        if (output.length < required)
            return null;

        put4(output, 0, cast(uint) year);
        output[4] = '-';
        put2(output, 5, cast(uint) calendar.tm_mon + 1);
        output[7] = '-';
        put2(output, 8, cast(uint) calendar.tm_mday);
        output[10] = zone == LogTimestampZone.utc ? 'T' : ' ';
        put2(output, 11, cast(uint) calendar.tm_hour);
        output[13] = ':';
        put2(output, 14, cast(uint) calendar.tm_min);
        output[16] = ':';
        put2(output, 17, cast(uint) calendar.tm_sec);

        size_t length = 19;
        if (milliseconds)
        {
            output[length++] = '.';
            put3(output, length, cast(uint)(remainder / 1_000_000));
            length += 3;
        }
        if (zone == LogTimestampZone.utc)
            output[length++] = 'Z';
        return output[0 .. length];
    }
    else
        return null;
}

private void put2(char[] output, size_t offset, uint value)
pure @safe
{
    output[offset] = cast(char)('0' + (value / 10) % 10);
    output[offset + 1] = cast(char)('0' + value % 10);
}

private void put3(char[] output, size_t offset, uint value)
pure @safe
{
    output[offset] = cast(char)('0' + (value / 100) % 10);
    output[offset + 1] = cast(char)('0' + (value / 10) % 10);
    output[offset + 2] = cast(char)('0' + value % 10);
}

private void put4(char[] output, size_t offset, uint value)
pure @safe
{
    output[offset] = cast(char)('0' + (value / 1000) % 10);
    output[offset + 1] = cast(char)('0' + (value / 100) % 10);
    output[offset + 2] = cast(char)('0' + (value / 10) % 10);
    output[offset + 3] = cast(char)('0' + value % 10);
}

version (unittest)
{
    private struct FixedClock
    {
        i64 nanoseconds;
        OsError error;
        size_t calls;
    }

    private OsError fixedClock(void* context, i64* output)
    {
        FixedClock* clock = cast(FixedClock*) context;
        if (clock is null || output is null)
            return OsError.init;
        ++clock.calls;
        if (clock.error.failed)
            return clock.error;
        *output = clock.nanoseconds;
        return OsError.init;
    }

    private struct PrefixCapture
    {
        char[64] bytes;
        size_t length;
        AnsiStyle style;
        size_t writes;
    }

    private bool prefixCaptureSink(void* context, scope const LogSinkEvent* event)
    {
        PrefixCapture* capture = cast(PrefixCapture*) context;
        if (capture is null || event is null)
            return false;
        if (event.kind != LogSinkEventKind.text)
            return true;
        if (capture.length + event.bytes.length > capture.bytes.length)
            return false;
        foreach (value; event.bytes)
            capture.bytes[capture.length++] = value;
        if (capture.writes == 0)
            capture.style = event.style;
        ++capture.writes;
        return true;
    }
}

unittest
{
    import xtb.log.prefix_sink : PrefixLogSink;
    import xtb.log.sink : LogSinkEvent, LogSinkEventKind, LogSinkRef;
    import xtb.string;
    import xtb.os.error : OsErrorKind;

    static assert(!__traits(isCopyable, TimestampLogPrefix));

    const defaultOptions = LogTimestampOptions.defaults();
    assert(defaultOptions.zone == LogTimestampZone.local);
    assert(!defaultOptions.milliseconds);
    assert(defaultOptions.separator.equal(" "));
    assert(defaultOptions.style == AnsiStyle.foreground(AnsiColor.brightBlack).dim);

    LogTimestampOptions options = defaultOptions;
    options.zone = LogTimestampZone.utc;
    options.milliseconds = true;
    options.style = AnsiStyle.foreground(AnsiColor.rgb(120, 130, 140));
    options.separator = " | ";

    // 2024-02-29T12:34:56.789Z, exercising leap-day formatting.
    FixedClock clock;
    clock.nanoseconds = 1_709_210_096_789_000_000L;
    TimestampLogPrefix timestamp = TimestampLogPrefix.createWithClock(
        options,
        &fixedClock,
        &clock,
    );
    PrefixCapture capture;
    PrefixLogSink prefixed = PrefixLogSink.create(
        LogSinkRef.create(&prefixCaptureSink, &capture),
        timestamp.prefixRef(),
    );

    const recordInfo = LogRecordInfo(LogLevel.info);
    LogSinkRef sink = prefixed.sinkRef();
    LogRecordRef record = sink.beginRecord(recordInfo);
    assert(record.valid);
    assert(record.endRecord());
    assert(clock.calls == 1);
    assert(cast(String) capture.bytes[0 .. capture.length] ==
            "2024-02-29T12:34:56.789Z | ");
    assert(capture.writes == 2);
    assert(capture.style == options.style);

    char[32] buffer;
    assert(formatTimestamp(
            0,
            LogTimestampZone.utc,
            false,
            buffer[],
    ).equal("1970-01-01T00:00:00Z"));
    assert(formatTimestamp(
            999_000_000,
            LogTimestampZone.utc,
            true,
            buffer[],
    ).equal("1970-01-01T00:00:00.999Z"));
    assert(formatTimestamp(
            0,
            LogTimestampZone.utc,
            false,
            buffer[0 .. 8],
    ).length == 0);
    assert(formatTimestamp(
            0,
            LogTimestampZone.local,
            false,
            buffer[],
    ).length == 19);
    assert(formatTimestamp(
            0,
            LogTimestampZone.local,
            false,
            buffer[0 .. 19],
    ).length == 19);
    assert(formatTimestamp(
            999_000_000,
            LogTimestampZone.local,
            true,
            buffer[0 .. 23],
    ).length == 23);

    LogTimestampOptions unstyledOptions = options;
    unstyledOptions.style = AnsiStyle.init;
    unstyledOptions.separator = null;
    FixedClock unstyledClock;
    unstyledClock.nanoseconds = clock.nanoseconds;
    TimestampLogPrefix unstyled = TimestampLogPrefix.createWithClock(
        unstyledOptions,
        &fixedClock,
        &unstyledClock,
    );
    PrefixCapture unstyledCapture;
    PrefixLogSink unstyledSink = PrefixLogSink.create(
        LogSinkRef.create(&prefixCaptureSink, &unstyledCapture),
        unstyled.prefixRef(),
    );
    LogSinkRef unstyledRef = unstyledSink.sinkRef();
    LogRecordRef unstyledRecord = unstyledRef.beginRecord(recordInfo);
    assert(unstyledRecord.valid);
    assert(unstyledRecord.endRecord());
    assert(unstyledCapture.writes == 1);
    assert(!unstyledCapture.style.enabled);

    FixedClock failingClock;
    failingClock.error = OsError(OsErrorKind.system, 1);
    TimestampLogPrefix failing = TimestampLogPrefix.createWithClock(
        options,
        &fixedClock,
        &failingClock,
    );
    PrefixCapture failureCapture;
    PrefixLogSink failureSink = PrefixLogSink.create(
        LogSinkRef.create(&prefixCaptureSink, &failureCapture),
        failing.prefixRef(),
    );
    LogSinkRef failureRef = failureSink.sinkRef();
    LogRecordRef failureRecord = failureRef.beginRecord(recordInfo);
    assert(failureRecord.valid);
    assert(!failureRecord.endRecord());
    assert(failingClock.calls == 1);
    assert(failureCapture.length == 0);
}

unittest
{
    import core.stdc.stdio : FILE, fclose, fread, rewind, tmpfile;
    import xtb.log.file_sink : ansiFileLogSink, plainFileLogSink;
    import xtb.log.level : LogLevel;
    import xtb.log.logger : Logger, flush, info;
    import xtb.log.prefix_sink : PrefixLogSink;
    import xtb.log.tee_sink : TeeLogSink;
    import xtb.string;

    size_t readFile(FILE* file, char[] destination) @system
    {
        rewind(file);
        return fread(destination.ptr, 1, destination.length, file);
    }

    LogTimestampOptions options = LogTimestampOptions.defaults();
    options.zone = LogTimestampZone.utc;
    options.style = AnsiStyle.foreground(AnsiColor.rgb(90, 100, 110)).dim;

    FixedClock sharedClock;
    sharedClock.nanoseconds = 1_704_067_200_000_000_000L; // 2024-01-01T00:00:00Z
    TimestampLogPrefix sharedTimestamp = TimestampLogPrefix.createWithClock(
        options,
        &fixedClock,
        &sharedClock,
    );

    FILE* ansiFile = tmpfile();
    assert(ansiFile !is null);
    scope (exit)
        assert(fclose(ansiFile) == 0);
    FILE* plainFile = tmpfile();
    assert(plainFile !is null);
    scope (exit)
        assert(fclose(plainFile) == 0);

    TeeLogSink sharedOutputs = TeeLogSink.create(
        ansiFileLogSink(ansiFile),
        plainFileLogSink(plainFile),
    );
    PrefixLogSink sharedPrefix = PrefixLogSink.create(
        sharedOutputs.sinkRef(),
        sharedTimestamp.prefixRef(),
    );
    char[128] storage;
    Logger sharedLogger = Logger.create(
        sharedPrefix.sinkRef(),
        storage[],
        LogLevel.info,
    );
    assert(sharedLogger.info("started").delivered);
    assert(sharedLogger.flush());

    char[256] ansiBytes;
    char[256] plainBytes;
    const ansiLength = readFile(ansiFile, ansiBytes[]);
    const plainLength = readFile(plainFile, plainBytes[]);
    const ansiText = cast(String) ansiBytes[0 .. ansiLength];
    const plainText = cast(String) plainBytes[0 .. plainLength];
    assert(ansiText.contains("2024-01-01T00:00:00Z"));
    assert(ansiText.contains("\x1b[2;38;2;90;100;110m"));
    assert(plainText.equal("2024-01-01T00:00:00Z [info]    started\n"));
    foreach (value; plainText)
        assert(value != '\x1b');

    FILE* terminal = tmpfile();
    assert(terminal !is null);
    scope (exit)
        assert(fclose(terminal) == 0);
    FILE* logfile = tmpfile();
    assert(logfile !is null);
    scope (exit)
        assert(fclose(logfile) == 0);

    FixedClock fileClock;
    fileClock.nanoseconds = sharedClock.nanoseconds;
    TimestampLogPrefix fileTimestamp = TimestampLogPrefix.createWithClock(
        options,
        &fixedClock,
        &fileClock,
    );
    PrefixLogSink timestampedFile = PrefixLogSink.create(
        plainFileLogSink(logfile),
        fileTimestamp.prefixRef(),
    );
    TeeLogSink splitOutputs = TeeLogSink.create(
        plainFileLogSink(terminal),
        timestampedFile.sinkRef(),
    );
    Logger splitLogger = Logger.create(
        splitOutputs.sinkRef(),
        storage[],
        LogLevel.info,
    );
    assert(splitLogger.info("file only").delivered);
    assert(splitLogger.flush());

    char[128] terminalBytes;
    char[128] logBytes;
    const terminalLength = readFile(terminal, terminalBytes[]);
    const logLength = readFile(logfile, logBytes[]);
    assert(cast(String) terminalBytes[0 .. terminalLength] == "[info]    file only\n");
    assert(cast(String) logBytes[0 .. logLength] ==
            "2024-01-01T00:00:00Z [info]    file only\n");
}
