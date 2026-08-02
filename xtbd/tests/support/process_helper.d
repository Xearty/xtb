module tests.support.process_helper;

nothrow @nogc:

import core.stdc.errno : EINTR, errno;
import core.stdc.signal : raise;
import core.stdc.stdlib : getenv;
import core.stdc.string : strcmp, strlen;
import core.sys.posix.time : nanosleep, timespec;
import core.sys.posix.unistd : STDERR_FILENO, STDIN_FILENO, STDOUT_FILENO,
    getcwd, read, write;

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

extern (C) int main(int argumentCount, char** arguments) @system
{
    if (argumentCount < 2)
        return 2;
    if (equal(arguments[1], "argv"))
        return emitArguments(argumentCount, arguments);
    if (equal(arguments[1], "environment"))
        return emitEnvironment(argumentCount, arguments);
    if (equal(arguments[1], "copy"))
        return copyInput();
    if (equal(arguments[1], "emit"))
    {
        enum ubyte[8] output = ['o', 'u', 't', 0, 'd', 'a', 't', 'a'];
        enum ubyte[10] error = ['e', 'r', 'r', 'o', 'r', '-', 'd', 'a', 't', 'a'];
        return writeEntire(STDOUT_FILENO, output.ptr, output.length) &&
            writeEntire(STDERR_FILENO, error.ptr, error.length) ? 0 : 120;
    }
    if (equal(arguments[1], "cwd"))
        return emitCurrentDirectory();
    if (equal(arguments[1], "exit") && argumentCount == 3)
    {
        const code = parseNonnegative(arguments[2]);
        return code >= 0 && code <= 255 ? code : 2;
    }
    if (equal(arguments[1], "signal") && argumentCount == 3)
    {
        const signal = parseNonnegative(arguments[2]);
        return signal > 0 && raise(signal) == 0 ? 124 : 2;
    }
    if (equal(arguments[1], "sleep-ms") && argumentCount == 3)
        return sleepMilliseconds(arguments[2]);
    return 2;
}
