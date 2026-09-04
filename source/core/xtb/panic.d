module xtb.panic;

nothrow @nogc:

import core.stdc.stdio : FILE, fflush, fwrite, stderr;
import core.stdc.stdlib : abort, exit;
import xtb.types;

alias PanicHandler = void function(String message, void* context);

struct PanicHook
{
    PanicHandler handler;
    void* context;
}

private __gshared PanicHook panic_hook;
// Panic recursion remains local to the panicking thread.
private bool panic_in_flight;

/// Installs a process-wide handler and returns the previously installed hook.
///
/// The caller must ensure that `handler` is safe to invoke with `context`, keep
/// both valid until the hook is replaced, and change the hook only while
/// application worker threads are stopped.
PanicHook set_panic_handler(PanicHandler handler, void* context = null) @system
{
    PanicHook previous = panic_hook;
    panic_hook = PanicHook(handler, context);
    return previous;
}

private void raw_panic_write(String message)
{
    enum prefix = "panic: ";
    cast(void) fwrite(prefix.ptr, 1, prefix.length, cast(FILE*) stderr);

    if (message.length != 0)
        cast(void) fwrite(message.ptr, 1, message.length, cast(FILE*) stderr);

    enum newline = "\n";
    cast(void) fwrite(newline.ptr, 1, newline.length, cast(FILE*) stderr);
}

noreturn panic(String message) @trusted
{
    if (panic_in_flight)
    {
        raw_panic_write("recursive panic");
        cast(void) fflush(null);
        exit(127);
    }

    panic_in_flight = true;

    // The @system installer owns callback and context validity as well as
    // synchronization with this read. Native writes use valid slice bounds.
    if (panic_hook.handler !is null)
        panic_hook.handler(message, panic_hook.context);

    raw_panic_write(message);
    cast(void) fflush(null);
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

private void append_decimal(ref char[1024] buffer, ref usize length, usize value)
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

private noreturn panic_at(String message, String file, usize line)
{
    char[1024] buffer;
    usize length;

    append(buffer, length, message);
    append(buffer, length, " (");
    append(buffer, length, file);
    append(buffer, length, ":");
    append_decimal(buffer, length, line);
    append(buffer, length, ")");

    if (length == buffer.length)
        buffer[$ - 3 .. $] = "...";

    panic(buffer[0 .. length]);
}

version (XTB_Checked)
{
    /// Enforces a programmer contract in checked builds.
    void require(string file = __FILE__, usize line = __LINE__)(
        bool condition,
        String message,
    ) @trusted
    {
        if (!condition) panic_at(message, file, line);
    }

    /// Verifies an implementation guarantee in checked builds.
    void ensure(string file = __FILE__, usize line = __LINE__)(
        bool condition,
        String message,
    ) @trusted
    {
        if (!condition) panic_at(message, file, line);
    }
}
else
{
    /// Omits a programmer contract and its arguments in unchecked builds.
    void require(string file = __FILE__, usize line = __LINE__)(
        lazy bool,
        lazy String,
    ) @trusted
    {}

    /// Omits an implementation guarantee and its arguments in unchecked builds.
    void ensure(string file = __FILE__, usize line = __LINE__)(
        lazy bool,
        lazy String,
    ) @trusted
    {}
}

noreturn unreachable_code(
    string file = __FILE__,
    usize line = __LINE__,
)() @trusted
{
    panic_at("unreachable code reached", file, line);
}

unittest
{
    static assert(__traits(compiles, () @safe
    {
        panic("compile-only safety check");
    }));
    static assert(!__traits(compiles, () @safe
    {
        cast(void) set_panic_handler(null);
    }));
}
