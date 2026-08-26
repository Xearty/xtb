module xtb.log.file_sink;

nothrow @nogc:

import core.stdc.stdio : FILE, fflush, fwrite, stderr, stdout;
import core.stdc.string : memchr;
import xtb.ansi : AnsiStyle, ansiResetSequence, ansiSequence;
import xtb.log.internal.sgr : SgrParseKind, parseSgrPrefix;
import xtb.log.level : LogLevel;
import xtb.log.logger : Logger;
import xtb.log.palette : LogPalette;
import xtb.log.sink : LogSinkEvent, LogSinkEventKind, LogSinkRef;
import xtb.string : String;

enum LogStyle : ubyte
{
    plain,
    ansi,
}

private bool writeAll(FILE* file, String value)
{
    return value.length == 0 || fwrite(value.ptr, 1, value.length, file) == value.length;
}

private size_t findEscape(scope String bytes, size_t start = 0)
@trusted
{
    if (start >= bytes.length)
        return bytes.length;
    const found = memchr(bytes.ptr + start, '\x1b', bytes.length - start);
    return found is null
        ? bytes.length : cast(const(char)*) found - bytes.ptr;
}

private bool writePlainText(FILE* file, scope String bytes)
{
    size_t plainStart;
    size_t searchStart;
    while (searchStart < bytes.length)
    {
        const escape = findEscape(bytes, searchStart);
        if (escape == bytes.length)
            break;

        const parsed = parseSgrPrefix(bytes[escape .. $]);
        if (parsed.kind != SgrParseKind.complete)
        {
            searchStart = escape + 1;
            continue;
        }

        if (!writeAll(file, bytes[plainStart .. escape]))
            return false;
        plainStart = escape + parsed.length;
        searchStart = plainStart;
    }
    return writeAll(file, bytes[plainStart .. $]);
}

private bool writeAnsiText(FILE* file, scope String bytes, AnsiStyle baseStyle)
{
    if (!baseStyle.enabled)
        return writeAll(file, bytes);

    const firstEscape = findEscape(bytes);
    if (firstEscape == bytes.length)
        return writeAll(file, bytes);

    const baseSequence = ansiSequence(baseStyle);
    size_t spanStart;
    size_t searchStart = firstEscape;
    while (searchStart < bytes.length)
    {
        const escape = findEscape(bytes, searchStart);
        if (escape == bytes.length)
            break;

        const parsed = parseSgrPrefix(bytes[escape .. $]);
        if (parsed.kind == SgrParseKind.complete && parsed.fullReset)
        {
            const resetEnd = escape + parsed.length;
            if (!writeAll(file, bytes[spanStart .. resetEnd]))
                return false;
            if (!baseSequence.empty && !writeAll(file, baseSequence.view))
                return false;
            spanStart = resetEnd;
            searchStart = resetEnd;
            continue;
        }
        searchStart = escape + 1;
    }
    return writeAll(file, bytes[spanStart .. $]);
}

private bool plainFileSinkCallback(void* context, scope const LogSinkEvent* event)
{
    FILE* file = cast(FILE*) context;
    if (file is null || event is null)
        return false;

    final switch (event.kind)
    {
        case LogSinkEventKind.beginRecord:
            lockFile(file);
            return true;
        case LogSinkEventKind.text:
            return event.mayContainAnsi
                ? writePlainText(file, event.bytes) : writeAll(file, event.bytes);
        case LogSinkEventKind.messageChunk:
            return writePlainText(file, event.bytes);
        case LogSinkEventKind.beginMessage:
        case LogSinkEventKind.endMessage:
            return true;
        case LogSinkEventKind.endRecord:
            unlockFile(file);
            return true;
    }
}

private bool ansiFileSinkCallback(void* context, scope const LogSinkEvent* event)
{
    FILE* file = cast(FILE*) context;
    if (file is null || event is null)
        return false;

    const reset = ansiResetSequence();
    final switch (event.kind)
    {
        case LogSinkEventKind.beginRecord:
            lockFile(file);
            return true;
        case LogSinkEventKind.text:
        {
            const opening = ansiSequence(event.style);
            bool accepted = true;
            if (!opening.empty)
                accepted = writeAll(file, opening.view) && accepted;
            if (event.mayContainAnsi)
                accepted = writeAnsiText(file, event.bytes, event.style) && accepted;
            else
                accepted = writeAll(file, event.bytes) && accepted;
            if (!opening.empty || event.mayContainAnsi)
                accepted = writeAll(file, reset.view) && accepted;
            return accepted;
        }
        case LogSinkEventKind.beginMessage:
        {
            const opening = ansiSequence(event.style);
            return opening.empty || writeAll(file, opening.view);
        }
        case LogSinkEventKind.messageChunk:
            return writeAnsiText(file, event.bytes, event.style);
        case LogSinkEventKind.endMessage:
            return writeAll(file, reset.view);
        case LogSinkEventKind.endRecord:
            unlockFile(file);
            return true;
    }
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

package bool fileFlush(void* context)
{
    FILE* file = cast(FILE*) context;
    return file !is null && fflush(file) == 0;
}

/// Creates a borrowed plain file presentation sink.
///
/// Logger-generated styles are ignored. Supported embedded SGR sequences are
/// removed from arbitrary setup text such as prefixes and from message chunks;
/// known ANSI-free logger framing takes the direct-write path. `file` must
/// remain valid while the returned sink reference is used.
LogSinkRef plainFileLogSink(FILE* file)
{
    return LogSinkRef.create(
        &plainFileSinkCallback,
        cast(void*) file,
        &fileFlush,
    );
}

/// Creates a borrowed ANSI file/terminal presentation sink.
///
/// Logger-generated styles and supported embedded SGR in arbitrary setup text
/// or message chunks are preserved. Complete full resets restore the active
/// semantic style for that span; known ANSI-free logger framing avoids the SGR
/// scan. `file` must remain valid while the returned sink reference is used.
LogSinkRef ansiFileLogSink(FILE* file)
{
    return LogSinkRef.create(
        &ansiFileSinkCallback,
        cast(void*) file,
        &fileFlush,
    );
}

Logger fileLogger(
    FILE* file,
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
    LogPalette palette = LogPalette.defaults(),
)
{
    LogSinkRef sink = style == LogStyle.ansi
        ? ansiFileLogSink(file) : plainFileLogSink(file);
    return Logger.create(sink, messageBuffer, minimumLevel, palette);
}

Logger stderrLogger(
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
    LogPalette palette = LogPalette.defaults(),
)
{
    return fileLogger(
        cast(FILE*) stderr,
        messageBuffer,
        minimumLevel,
        style,
        palette,
    );
}

Logger stdoutLogger(
    return scope char[] messageBuffer,
    LogLevel minimumLevel = LogLevel.info,
    LogStyle style = LogStyle.plain,
    LogPalette palette = LogPalette.defaults(),
)
{
    return fileLogger(
        cast(FILE*) stdout,
        messageBuffer,
        minimumLevel,
        style,
        palette,
    );
}
