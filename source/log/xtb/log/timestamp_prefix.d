module xtb.log.timestamp_prefix;

nothrow @nogc:

version (Posix)
{
    import core.sys.posix.stdc.time;
    import core.sys.posix.time;
}

import xtb.ansi;
import xtb.log.prefix_sink;
import xtb.time;
import xtb.types;

enum LogTimestampZone : u8
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
    ANSIStyle style;
    String separator;

    static LogTimestampOptions defaults() @safe
    {
        LogTimestampOptions result;
        result.zone = LogTimestampZone.local;
        result.style = ANSIStyle.foreground(ANSIColor.bright_black).dim;
        result.separator = " ";
        return result;
    }
}

/// Non-owning wall-clock timestamp prefix provider.
///
/// The provider samples `xtb.time.Timestamp`, formats it into fixed stack
/// storage, and emits it synchronously through `LogPrefixWriter`.
/// `prefix_ref()` borrows this value, so it must remain at a stable address
/// while the returned reference is used.
struct TimestampLogPrefix
{
nothrow @nogc:

    /// Formatting policy. Its borrowed `separator` must remain valid while
    /// prefix references created from this provider are used.
    LogTimestampOptions options;

    @disable this(this);

    static TimestampLogPrefix create(
        return scope LogTimestampOptions options = LogTimestampOptions.defaults(),
    ) @safe
    {
        TimestampLogPrefix result;
        result.options = options;
        return result;
    }

    LogPrefixRef prefix_ref() return @trusted
    {
        // The callback receives exactly &this as its opaque context, and
        // `return` prevents the reference from outliving this provider.
        return LogPrefixRef.create(&try_write_timestamp_prefix_callback, &this);
    }
}

private bool try_write_timestamp_prefix_callback(
    void* context,
    scope LogPrefixWriter* output,
) @system
{
    auto timestamp = cast(TimestampLogPrefix*) context;
    if (timestamp is null || output is null) return false;

    const now = Timestamp.now();
    return try_write_timestamp_prefix(
        timestamp.options,
        now.nanosecondsSinceUnixEpoch,
        output,
    );
}

private bool try_write_timestamp_prefix(
    LogTimestampOptions options,
    i64 nanoseconds,
    scope LogPrefixWriter* output,
) @system
{
    if (output is null) return false;

    char[32] storage;
    const String formatted = format_timestamp(
        nanoseconds,
        options.zone,
        options.milliseconds,
        storage[],
    );
    if (formatted.length == 0) return false;
    if (!output.try_write(formatted, options.style)) return false;

    return options.separator.length == 0 || output.try_write(options.separator);
}

private String format_timestamp(
    i64 nanoseconds,
    LogTimestampZone zone,
    bool milliseconds,
    return scope char[] output,
) @system
{
    enum i64 nanoseconds_per_second = 1_000_000_000L;
    i64 seconds = nanoseconds / nanoseconds_per_second;
    i64 remainder = nanoseconds % nanoseconds_per_second;
    if (remainder < 0)
    {
        --seconds;
        remainder += nanoseconds_per_second;
    }

    version (Posix)
    {
        const native_seconds = cast(time_t) seconds;
        if (cast(i64) native_seconds != seconds) return null;

        tm calendar;
        tm* converted = zone == LogTimestampZone.utc
            ? gmtime_r(&native_seconds, &calendar)
            : localtime_r(&native_seconds, &calendar);
        if (converted is null) return null;

        const year = calendar.tm_year + 1900;
        if (year < 0 || year > 9999) return null;

        const usize base_length = zone == LogTimestampZone.utc ? 20 : 19;
        const usize required_length = base_length + (milliseconds ? 4 : 0);
        if (output.length < required_length) return null;

        put_four_digits(output, 0, cast(u32) year);
        output[4] = '-';
        put_two_digits(output, 5, cast(u32) calendar.tm_mon + 1);
        output[7] = '-';
        put_two_digits(output, 8, cast(u32) calendar.tm_mday);
        output[10] = zone == LogTimestampZone.utc ? 'T' : ' ';
        put_two_digits(output, 11, cast(u32) calendar.tm_hour);
        output[13] = ':';
        put_two_digits(output, 14, cast(u32) calendar.tm_min);
        output[16] = ':';
        put_two_digits(output, 17, cast(u32) calendar.tm_sec);

        usize length = 19;
        if (milliseconds)
        {
            output[length++] = '.';
            put_three_digits(output, length, cast(u32)(remainder / 1_000_000));
            length += 3;
        }
        if (zone == LogTimestampZone.utc) output[length++] = 'Z';

        return output[0 .. length];
    }
    else
    {
        return null;
    }
}

private void put_two_digits(scope char[] output, usize offset, u32 value) pure @safe
{
    output[offset] = cast(char)('0' + (value / 10) % 10);
    output[offset + 1] = cast(char)('0' + value % 10);
}

private void put_three_digits(scope char[] output, usize offset, u32 value) pure @safe
{
    output[offset] = cast(char)('0' + (value / 100) % 10);
    output[offset + 1] = cast(char)('0' + (value / 10) % 10);
    output[offset + 2] = cast(char)('0' + value % 10);
}

private void put_four_digits(scope char[] output, usize offset, u32 value) pure @safe
{
    output[offset] = cast(char)('0' + (value / 1000) % 10);
    output[offset + 1] = cast(char)('0' + (value / 100) % 10);
    output[offset + 2] = cast(char)('0' + (value / 10) % 10);
    output[offset + 3] = cast(char)('0' + value % 10);
}

version (unittest)
{
    import core.stdc.stdio;

    import xtb.log.file_sink;
    import xtb.log.level;
    import xtb.log.logger;
    import xtb.log.sink;
    import xtb.log.tee_sink;
    import xtb.string;

    private struct FixedTimestampPrefix
    {
        LogTimestampOptions options;
        i64 nanoseconds;
    }

    private bool try_write_fixed_timestamp_prefix(
        void* context,
        scope LogPrefixWriter* output,
    ) @system
    {
        auto timestamp = cast(FixedTimestampPrefix*) context;
        return timestamp !is null
            && try_write_timestamp_prefix(timestamp.options, timestamp.nanoseconds, output);
    }

    private struct PrefixCapture
    {
        char[64] bytes;
        usize length;
        ANSIStyle style;
        usize writes;
    }

    private bool try_capture_prefix(void* context, scope const LogSinkEvent* event) @system
    {
        auto capture = cast(PrefixCapture*) context;
        if (capture is null || event is null) return false;
        if (event.kind != LogSinkEventKind.text) return true;
        if (capture.length + event.bytes.length > capture.bytes.length) return false;

        foreach (value; event.bytes)
            capture.bytes[capture.length++] = value;

        if (capture.writes == 0) capture.style = event.style;

        ++capture.writes;
        return true;
    }
}

unittest
{
    static assert(!__traits(isCopyable, TimestampLogPrefix));

    const default_options = LogTimestampOptions.defaults();
    assert(default_options.zone == LogTimestampZone.local);
    assert(!default_options.milliseconds);
    assert(default_options.separator.equal(" "));
    assert(default_options.style == ANSIStyle.foreground(ANSIColor.bright_black).dim);

    LogTimestampOptions options = default_options;
    options.zone = LogTimestampZone.utc;
    options.milliseconds = true;
    options.style = ANSIStyle.foreground(ANSIColor.rgb(120, 130, 140));
    options.separator = " | ";

    auto timestamp = TimestampLogPrefix.create(options);
    assert(timestamp.prefix_ref().valid);

    FixedTimestampPrefix fixed;
    fixed.options = options;
    // 2024-02-29T12:34:56.789Z, exercising leap-day formatting.
    fixed.nanoseconds = 1_709_210_096_789_000_000L;

    PrefixCapture capture;
    auto prefixed = PrefixLogSink.create(
        LogSinkRef.create(&try_capture_prefix, &capture),
        LogPrefixRef.create(&try_write_fixed_timestamp_prefix, &fixed),
    );

    const record_info = LogRecordInfo(LogLevel.info);
    LogSinkRef sink = prefixed.sink_ref();
    LogRecordRef record = sink.begin_record(record_info);
    assert(record.valid);
    assert(record.try_end_record());
    assert(cast(String) capture.bytes[0 .. capture.length] == "2024-02-29T12:34:56.789Z | ");
    assert(capture.writes == 2);
    assert(capture.style == options.style);

    char[32] buffer;
    const String epoch_utc = format_timestamp(0, LogTimestampZone.utc, false, buffer[]);
    assert(epoch_utc.equal("1970-01-01T00:00:00Z"));

    const String epoch_utc_milliseconds = format_timestamp(
        999_000_000,
        LogTimestampZone.utc,
        true,
        buffer[],
    );
    assert(epoch_utc_milliseconds.equal("1970-01-01T00:00:00.999Z"));

    const String short_utc = format_timestamp(0, LogTimestampZone.utc, false, buffer[0 .. 8]);
    assert(short_utc.length == 0);

    const String epoch_local = format_timestamp(0, LogTimestampZone.local, false, buffer[]);
    assert(epoch_local.length == 19);

    const String exact_local = format_timestamp(
        0,
        LogTimestampZone.local,
        false,
        buffer[0 .. 19],
    );
    assert(exact_local.length == 19);

    const String exact_local_milliseconds = format_timestamp(
        999_000_000,
        LogTimestampZone.local,
        true,
        buffer[0 .. 23],
    );
    assert(exact_local_milliseconds.length == 23);

    LogTimestampOptions unstyled_options = options;
    unstyled_options.style = ANSIStyle.init;
    unstyled_options.separator = null;
    FixedTimestampPrefix unstyled;
    unstyled.options = unstyled_options;
    unstyled.nanoseconds = fixed.nanoseconds;

    PrefixCapture unstyled_capture;
    auto unstyled_sink = PrefixLogSink.create(
        LogSinkRef.create(&try_capture_prefix, &unstyled_capture),
        LogPrefixRef.create(&try_write_fixed_timestamp_prefix, &unstyled),
    );
    LogSinkRef unstyled_ref = unstyled_sink.sink_ref();
    LogRecordRef unstyled_record = unstyled_ref.begin_record(record_info);
    assert(unstyled_record.valid);
    assert(unstyled_record.try_end_record());
    assert(unstyled_capture.writes == 1);
    assert(!unstyled_capture.style.enabled);
}

unittest
{
    usize read_file(FILE* file, scope char[] destination) @system
    {
        rewind(file);
        return fread(destination.ptr, 1, destination.length, file);
    }

    LogTimestampOptions options = LogTimestampOptions.defaults();
    options.zone = LogTimestampZone.utc;
    options.style = ANSIStyle.foreground(ANSIColor.rgb(90, 100, 110)).dim;

    auto shared_timestamp = TimestampLogPrefix.create(options);

    FILE* ansi_file = tmpfile();
    assert(ansi_file !is null);
    scope (exit) assert(fclose(ansi_file) == 0);

    FILE* plain_file = tmpfile();
    assert(plain_file !is null);
    scope (exit) assert(fclose(plain_file) == 0);

    auto shared_outputs = TeeLogSink.create(
        ansi_file_log_sink(ansi_file),
        plain_file_log_sink(plain_file),
    );
    auto shared_prefix = PrefixLogSink.create(
        shared_outputs.sink_ref(),
        shared_timestamp.prefix_ref(),
    );
    char[128] storage;
    auto shared_logger = Logger.create(shared_prefix.sink_ref(), storage[], LogLevel.info);
    assert(shared_logger.info("started").delivered);
    assert(shared_logger.try_flush());

    char[256] ansi_bytes;
    char[256] plain_bytes;
    const usize ansi_length = read_file(ansi_file, ansi_bytes[]);
    const usize plain_length = read_file(plain_file, plain_bytes[]);
    const ansi_text = cast(String) ansi_bytes[0 .. ansi_length];
    const plain_text = cast(String) plain_bytes[0 .. plain_length];
    assert(ansi_text.contains("\x1b[2;38;2;90;100;110m"));
    assert(ansi_text.ends_with("started\x1b[0m\n"));
    assert(plain_text.length > " [info]    started\n".length);
    assert(plain_text.ends_with(" [info]    started\n"));
    foreach (value; plain_text)
        assert(value != '\x1b');

    FILE* terminal = tmpfile();
    assert(terminal !is null);
    scope (exit) assert(fclose(terminal) == 0);

    FILE* log_file = tmpfile();
    assert(log_file !is null);
    scope (exit) assert(fclose(log_file) == 0);

    auto file_timestamp = TimestampLogPrefix.create(options);
    auto timestamped_file = PrefixLogSink.create(
        plain_file_log_sink(log_file),
        file_timestamp.prefix_ref(),
    );
    auto split_outputs = TeeLogSink.create(
        plain_file_log_sink(terminal),
        timestamped_file.sink_ref(),
    );
    auto split_logger = Logger.create(split_outputs.sink_ref(), storage[], LogLevel.info);
    assert(split_logger.info("file only").delivered);
    assert(split_logger.try_flush());

    char[128] terminal_bytes;
    char[128] log_bytes;
    const usize terminal_length = read_file(terminal, terminal_bytes[]);
    const usize log_length = read_file(log_file, log_bytes[]);
    const terminal_text = cast(String) terminal_bytes[0 .. terminal_length];
    const log_text = cast(String) log_bytes[0 .. log_length];
    assert(terminal_text == "[info]    file only\n");
    assert(log_text.length > " [info]    file only\n".length);
    assert(log_text.ends_with(" [info]    file only\n"));
}
