module xtb.log.file_sink;

nothrow @nogc:

import core.stdc.stdio : FILE, fflush, fwrite, stderr, stdout;
import core.stdc.string : memchr;

import xtb.ansi;
import xtb.log.internal.sgr;
import xtb.log.level;
import xtb.log.logger;
import xtb.log.palette;
import xtb.log.sink;
import xtb.types;

enum LogStyle : u8
{
    plain,
    ansi,
}

private bool try_write_all(FILE* file, String value)
{
    return value.length == 0 || fwrite(value.ptr, 1, value.length, file) == value.length;
}

private usize find_escape(scope String bytes, usize start = 0) @trusted
{
    if (start >= bytes.length) return bytes.length;

    // `start` is in range, so the pointer and byte count passed to memchr stay
    // within `bytes`; the returned pointer is used only to compute an index.
    const(void)* found = memchr(bytes.ptr + start, '\x1b', bytes.length - start);
    return found is null ? bytes.length : cast(const(char)*) found - bytes.ptr;
}

private bool try_write_plain_text(FILE* file, scope String bytes)
{
    usize plain_start;
    usize search_start;
    while (search_start < bytes.length)
    {
        const usize escape = find_escape(bytes, search_start);
        if (escape == bytes.length) break;

        const SGRParseResult parsed = parse_sgr_prefix(bytes[escape .. $]);
        if (parsed.kind != SGRParseKind.complete)
        {
            search_start = escape + 1;
            continue;
        }

        if (!try_write_all(file, bytes[plain_start .. escape])) return false;

        plain_start = escape + parsed.length;
        search_start = plain_start;
    }

    return try_write_all(file, bytes[plain_start .. $]);
}

private bool try_write_ansi_text(FILE* file, scope String bytes, ANSIStyle base_style)
{
    if (!base_style.enabled) return try_write_all(file, bytes);

    const usize first_escape = find_escape(bytes);
    if (first_escape == bytes.length) return try_write_all(file, bytes);

    const ANSISequence base_sequence = ansi_sequence(base_style);
    usize span_start;
    usize search_start = first_escape;
    while (search_start < bytes.length)
    {
        const usize escape = find_escape(bytes, search_start);
        if (escape == bytes.length) break;

        const SGRParseResult parsed = parse_sgr_prefix(bytes[escape .. $]);
        if (parsed.kind == SGRParseKind.complete && parsed.full_reset)
        {
            const usize reset_end = escape + parsed.length;
            if (!try_write_all(file, bytes[span_start .. reset_end])) return false;
            if (!base_sequence.empty && !try_write_all(file, base_sequence.view)) return false;

            span_start = reset_end;
            search_start = reset_end;
            continue;
        }

        search_start = escape + 1;
    }

    return try_write_all(file, bytes[span_start .. $]);
}

private bool try_plain_file_sink_event(void* context, scope const LogSinkEvent* event) @system
{
    auto file = cast(FILE*) context;
    if (file is null || event is null) return false;

    final switch (event.kind)
    {
    case LogSinkEventKind.begin_record:
        lock_file(file);
        return true;
    case LogSinkEventKind.text:
        return event.may_contain_ansi
            ? try_write_plain_text(file, event.bytes)
            : try_write_all(file, event.bytes);
    case LogSinkEventKind.message_chunk:
        return try_write_plain_text(file, event.bytes);
    case LogSinkEventKind.begin_message:
    case LogSinkEventKind.end_message:
        return true;
    case LogSinkEventKind.end_record:
        unlock_file(file);
        return true;
    }
}

private bool try_ansi_file_sink_event(void* context, scope const LogSinkEvent* event) @system
{
    auto file = cast(FILE*) context;
    if (file is null || event is null) return false;

    const ANSISequence reset = ansi_reset_sequence();
    final switch (event.kind)
    {
    case LogSinkEventKind.begin_record:
        lock_file(file);
        return true;
    case LogSinkEventKind.text:
    {
        const ANSISequence opening = ansi_sequence(event.style);
        bool accepted = true;
        if (!opening.empty) accepted = try_write_all(file, opening.view) && accepted;

        if (event.may_contain_ansi)
        {
            accepted = try_write_ansi_text(file, event.bytes, event.style) && accepted;
        }
        else
        {
            accepted = try_write_all(file, event.bytes) && accepted;
        }

        if (!opening.empty || event.may_contain_ansi)
        {
            accepted = try_write_all(file, reset.view) && accepted;
        }
        return accepted;
    }
    case LogSinkEventKind.begin_message:
    {
        const ANSISequence opening = ansi_sequence(event.style);
        return opening.empty || try_write_all(file, opening.view);
    }
    case LogSinkEventKind.message_chunk:
        return try_write_ansi_text(file, event.bytes, event.style);
    case LogSinkEventKind.end_message:
        return try_write_all(file, reset.view);
    case LogSinkEventKind.end_record:
        unlock_file(file);
        return true;
    }
}

private void lock_file(FILE* file)
{
    version (Posix)
    {
        import core.sys.posix.stdio : flockfile;

        flockfile(file);
    }
}

private void unlock_file(FILE* file)
{
    version (Posix)
    {
        import core.sys.posix.stdio : funlockfile;

        funlockfile(file);
    }
}

private bool try_file_flush(void* context) @system
{
    auto file = cast(FILE*) context;
    return file !is null && fflush(file) == 0;
}

/// Creates a borrowed plain file presentation sink.
///
/// Logger-generated styles are ignored. Supported embedded SGR sequences are
/// removed from arbitrary setup text such as prefixes and from message chunks;
/// known ANSI-free logger framing takes the direct-write path. `file` may be
/// null, in which case sink operations fail. A non-null `file` must remain valid
/// while the returned sink reference is used.
LogSinkRef plain_file_log_sink(FILE* file) @system
{
    return LogSinkRef.create(&try_plain_file_sink_event, cast(void*) file, &try_file_flush);
}

/// Creates a borrowed ANSI file/terminal presentation sink.
///
/// Logger-generated styles and supported embedded SGR in arbitrary setup text
/// or message chunks are preserved. Complete full resets restore the active
/// semantic style for that span; known ANSI-free logger framing avoids the SGR
/// scan. `file` may be null, in which case sink operations fail. A non-null
/// `file` must remain valid while the returned sink reference is used.
LogSinkRef ansi_file_log_sink(FILE* file) @system
{
    return LogSinkRef.create(&try_ansi_file_sink_event, cast(void*) file, &try_file_flush);
}

/// Creates a logger that writes to `file`.
///
/// `file` may be null, in which case sink operations fail. A non-null `file`
/// must remain valid while the returned logger is used.
Logger file_logger(
    FILE* file,
    return scope char[] message_buffer,
    LogLevel minimum_level = LogLevel.info,
    LogStyle style = LogStyle.plain,
    LogPalette palette = LogPalette.defaults(),
) @system
{
    LogSinkRef file_sink = style == LogStyle.ansi
        ? ansi_file_log_sink(file)
        : plain_file_log_sink(file);
    return Logger.create(file_sink, message_buffer, minimum_level, palette);
}

Logger stderr_logger(
    return scope char[] message_buffer,
    LogLevel minimum_level = LogLevel.info,
    LogStyle style = LogStyle.plain,
    LogPalette palette = LogPalette.defaults(),
) @trusted
{
    // `stderr` is the process-global C stream and outlives the returned logger.
    return file_logger(cast(FILE*) stderr, message_buffer, minimum_level, style, palette);
}

Logger stdout_logger(
    return scope char[] message_buffer,
    LogLevel minimum_level = LogLevel.info,
    LogStyle style = LogStyle.plain,
    LogPalette palette = LogPalette.defaults(),
) @trusted
{
    // `stdout` is the process-global C stream and outlives the returned logger.
    return file_logger(cast(FILE*) stdout, message_buffer, minimum_level, style, palette);
}
