module xtb.core.panic;

nothrow @nogc:

import core.stdc.stdlib : abort, exit;
import core.stdc.stdio : FILE, fflush, fwrite, stderr;
import xtb.core.types : String;

alias PanicHandler = void function(String message, void* context);

struct PanicHook
{
    PanicHandler handler;
    void* context;
}

// Installation is process-wide and must be changed only while application
// worker threads are stopped. Recursion remains local to the panicking thread.
private __gshared PanicHook panicHook;
private bool panicInFlight;

PanicHook setPanicHandler(PanicHandler handler, void* context = null)
{
    PanicHook previous = panicHook;
    panicHook = PanicHook(handler, context);
    return previous;
}

private void rawPanicWrite(String message)
{
    enum prefix = "panic: ";
    fwrite(prefix.ptr, 1, prefix.length, cast(FILE*) stderr);
    if (message.length != 0)
        fwrite(message.ptr, 1, message.length, cast(FILE*) stderr);
    enum newline = "\n";
    fwrite(newline.ptr, 1, newline.length, cast(FILE*) stderr);
}

noreturn panic(String message)
{
    if (panicInFlight)
    {
        rawPanicWrite("recursive panic");
        fflush(null);
        exit(127);
    }
    panicInFlight = true;

    if (panicHook.handler !is null)
        panicHook.handler(message, panicHook.context);
    rawPanicWrite(message);
    fflush(null);
    abort();
}

private void append(ref char[1024] buffer, ref size_t length, String value)
{
    const available = buffer.length - length;
    const amount = value.length < available ? value.length : available;
    foreach (index; 0 .. amount)
        buffer[length + index] = value[index];
    length += amount;
}

private void appendDecimal(ref char[1024] buffer, ref size_t length, size_t value)
{
    char[32] digits;
    size_t begin = digits.length;
    do
    {
        digits[--begin] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value != 0);
    append(buffer, length, digits[begin .. $]);
}

private noreturn panicAt(String message, String file, size_t line)
{
    char[1024] buffer;
    size_t length;
    append(buffer, length, message);
    append(buffer, length, " (");
    append(buffer, length, file);
    append(buffer, length, ":");
    appendDecimal(buffer, length, line);
    append(buffer, length, ")");
    if (length == buffer.length)
        buffer[$ - 3 .. $] = "...";
    panic(buffer[0 .. length]);
}

void require(string file = __FILE__, size_t line = __LINE__)(
    bool condition,
    String message,
) @trusted
{
    if (!condition)
        panicAt(message, file, line);
}

noreturn unreachableCode(
    string file = __FILE__,
    size_t line = __LINE__,
)() @trusted
{
    panicAt("unreachable code reached", file, line);
}
