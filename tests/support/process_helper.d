module tests.support.process_helper;

nothrow @nogc:

import core.stdc.errno : EINTR, errno;
import core.stdc.signal : raise;
import core.stdc.stdlib : getenv;
import core.stdc.string : strcmp, strlen;
import core.sys.posix.time : nanosleep, timespec;
import core.sys.posix.unistd : STDERR_FILENO, STDIN_FILENO, STDOUT_FILENO,
    getcwd, nativeClose = close, read, write;

private bool equal(const(char)* left, const(char)* right) @system
{
    return strcmp(left, right) == 0;
}

private int parseNonnegative(const(char)* value) @system
{
    if (value is null || *value == '\0')
        return -1;
    int result;
    while (*value != '\0')
    {
        if (*value < '0' || *value > '9' || result > (int.max - 9) / 10)
            return -1;
        result = result * 10 + (*value - '0');
        ++value;
    }
    return result;
}

private bool writeEntire(int descriptor, const(void)* data, size_t length) @system
{
    const(ubyte)* cursor = cast(const(ubyte)*) data;
    while (length != 0)
    {
        const amount = write(descriptor, cursor, length);
        if (amount > 0)
        {
            cursor += amount;
            length -= amount;
        }
        else if (amount < 0 && errno == EINTR)
            continue;
        else
            return false;
    }
    return true;
}

private bool writeCString(int descriptor, const(char)* value) @system
{
    return writeEntire(descriptor, value, strlen(value));
}

private int emitArguments(int argumentCount, char** arguments) @system
{
    if (!writeCString(STDOUT_FILENO, arguments[0]) ||
        !writeEntire(STDOUT_FILENO, "\0".ptr, 1))
        return 120;
    foreach (index; 2 .. argumentCount)
    {
        if (!writeCString(STDOUT_FILENO, arguments[index]) ||
            !writeEntire(STDOUT_FILENO, "\0".ptr, 1))
            return 120;
    }
    return 0;
}

private int emitEnvironment(int argumentCount, char** arguments) @system
{
    foreach (index; 2 .. argumentCount)
    {
        const value = getenv(arguments[index]);
        if (!writeCString(STDOUT_FILENO, arguments[index]))
            return 120;
        if (value !is null &&
            (!writeEntire(STDOUT_FILENO, "=".ptr, 1) ||
                !writeCString(STDOUT_FILENO, value)))
            return 120;
        if (!writeEntire(STDOUT_FILENO, "\0".ptr, 1))
            return 120;
    }
    return 0;
}

private int copyInput() @system
{
    ubyte[4096] buffer;
    for (;;)
    {
        const amount = read(STDIN_FILENO, buffer.ptr, buffer.length);
        if (amount > 0)
        {
            if (!writeEntire(STDOUT_FILENO, buffer.ptr, cast(size_t) amount))
                return 120;
        }
        else if (amount == 0)
            return 0;
        else if (errno != EINTR)
            return 121;
    }
}

private int floodThenCopy() @system
{
    enum chunkCount = 128;
    ubyte[1024] output;
    ubyte[1024] error;
    output[] = 'O';
    error[] = 'E';
    foreach (_; 0 .. chunkCount)
    {
        if (!writeEntire(STDOUT_FILENO, output.ptr, output.length) ||
            !writeEntire(STDERR_FILENO, error.ptr, error.length))
            return 120;
    }
    return copyInput();
}

private int emitCurrentDirectory() @system
{
    char[4096] buffer;
    const directory = getcwd(buffer.ptr, buffer.length);
    return directory !is null && writeCString(STDOUT_FILENO, directory)
        ? 0 : 122;
}

private int sleepMilliseconds(const(char)* text) @system
{
    const milliseconds = parseNonnegative(text);
    if (milliseconds < 0)
        return 2;
    timespec remaining;
    remaining.tv_sec = milliseconds / 1_000;
    remaining.tv_nsec = milliseconds % 1_000 * 1_000_000;
    for (;;)
    {
        timespec next;
        if (nanosleep(&remaining, &next) == 0)
            return 0;
        if (errno != EINTR)
            return 123;
        remaining = next;
    }
}

private immutable ubyte[8] emitOutput = ['o', 'u', 't', 0, 'd', 'a', 't', 'a'];
private immutable ubyte[10] emitError = ['e', 'r', 'r', 'o', 'r', '-', 'd', 'a', 't', 'a'];

private enum noCommandMatch = 256;

private alias CommandHandler = int function(
    int argumentCount,
    char** arguments,
) nothrow @nogc @system;

private int handleArgv(int argumentCount, char** arguments) @system
{
    return equal(arguments[1], "argv")
        ? emitArguments(argumentCount, arguments) : noCommandMatch;
}

private int handleEnvironment(int argumentCount, char** arguments) @system
{
    return equal(arguments[1], "environment")
        ? emitEnvironment(argumentCount, arguments) : noCommandMatch;
}

private int handleCopy(int, char** arguments) @system
{
    return equal(arguments[1], "copy") ? copyInput() : noCommandMatch;
}

private int handleFloodCopy(int, char** arguments) @system
{
    return equal(arguments[1], "flood-copy")
        ? floodThenCopy() : noCommandMatch;
}

private int handleCloseInput(int, char** arguments) @system
{
    if (!equal(arguments[1], "close-input"))
        return noCommandMatch;
    if (nativeClose(STDIN_FILENO) != 0)
        return 125;
    return writeEntire(STDOUT_FILENO, "closed".ptr, 6) ? 0 : 120;
}

private int handleEmit(int, char** arguments) @system
{
    if (!equal(arguments[1], "emit"))
        return noCommandMatch;
    return writeEntire(STDOUT_FILENO, emitOutput.ptr, emitOutput.length) &&
        writeEntire(STDERR_FILENO, emitError.ptr, emitError.length) ? 0 : 120;
}

private int handleCurrentDirectory(int, char** arguments) @system
{
    return equal(arguments[1], "cwd")
        ? emitCurrentDirectory() : noCommandMatch;
}

private int handleExit(int argumentCount, char** arguments) @system
{
    if (!equal(arguments[1], "exit"))
        return noCommandMatch;
    if (argumentCount != 3)
        return 2;
    const code = parseNonnegative(arguments[2]);
    return code >= 0 && code <= 255 ? code : 2;
}

private int handleSignal(int argumentCount, char** arguments) @system
{
    if (!equal(arguments[1], "signal"))
        return noCommandMatch;
    if (argumentCount != 3)
        return 2;
    const signalNumber = parseNonnegative(arguments[2]);
    return signalNumber > 0 && raise(signalNumber) == 0 ? 124 : 2;
}

private int handleSleep(int argumentCount, char** arguments) @system
{
    if (!equal(arguments[1], "sleep-ms"))
        return noCommandMatch;
    return argumentCount == 3 ? sleepMilliseconds(arguments[2]) : 2;
}

private int handleDelayedEmit(int argumentCount, char** arguments) @system
{
    if (!equal(arguments[1], "delayed-emit"))
        return noCommandMatch;
    if (argumentCount != 3)
        return 2;
    const sleepResult = sleepMilliseconds(arguments[2]);
    return sleepResult == 0 &&
        writeEntire(STDOUT_FILENO, "delayed".ptr, 7) ? 0 : 120;
}

extern (C) int main(int argumentCount, char** arguments) @system
{
    if (argumentCount < 2)
        return 2;

    CommandHandler[11] handlers = [
        &handleArgv,
        &handleEnvironment,
        &handleCopy,
        &handleFloodCopy,
        &handleCloseInput,
        &handleEmit,
        &handleCurrentDirectory,
        &handleExit,
        &handleSignal,
        &handleSleep,
        &handleDelayedEmit,
    ];
    foreach (handler; handlers)
    {
        const result = handler(argumentCount, arguments);
        if (result != noCommandMatch)
            return result;
    }
    return 2;
}
