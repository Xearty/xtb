module xtb.panic;

nothrow @nogc:

import core.stdc.stdlib : abort, exit;
import core.stdc.stdio : FILE, fflush, fwrite, stderr;
import xtb.types;

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

private void append(ref char[1024] buffer, ref usize length, String value)
{
    const available = buffer.length - length;
    const amount = value.length < available ? value.length : available;
    foreach (index; 0 .. amount)
        buffer[length + index] = value[index];
    length += amount;
}

private void appendDecimal(ref char[1024] buffer, ref usize length, usize value)
{
    char[32] digits;
    usize begin = digits.length;
    do
    {
        digits[--begin] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value != 0);
    append(buffer, length, digits[begin .. $]);
}

private noreturn panicAt(String message, String file, usize line)
{
    char[1024] buffer;
    usize length;
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

version (XTB_Checked) {
    /// Enforces a programmer contract in checked builds.
    void require(string file = __FILE__, usize line = __LINE__)(
        bool condition,
        String message,
    ) @trusted {
        if (!condition) {
            panicAt(message, file, line);
        }
    }

    /// Verifies an implementation guarantee in checked builds.
    void ensure(string file = __FILE__, usize line = __LINE__)(
        bool condition,
        String message,
    ) @trusted {
        if (!condition) {
            panicAt(message, file, line);
        }
    }
} else {
    /// Omits a programmer contract and its arguments in unchecked builds.
    void require(string file = __FILE__, usize line = __LINE__)(
        lazy bool,
        lazy String,
    ) @trusted {
    }

    /// Omits an implementation guarantee and its arguments in unchecked builds.
    void ensure(string file = __FILE__, usize line = __LINE__)(
        lazy bool,
        lazy String,
    ) @trusted {
    }
}

noreturn unreachableCode(
    string file = __FILE__,
    usize line = __LINE__,
)() @trusted
{
    panicAt("unreachable code reached", file, line);
}
