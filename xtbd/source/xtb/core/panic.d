module xtb.core.panic;

import core.stdc.stdlib : abort, exit;
import core.stdc.stdio : FILE, fflush, fwrite, stderr;
import xtb.core.print : formatBuffer;
import xtb.core.types : String;

alias PanicHandler = void function(String message, void* context) nothrow @nogc;

struct PanicHook
{
    PanicHandler handler;
    void* context;
}

private PanicHook panicHook;
private bool panicInFlight;

PanicHook setPanicHandler(PanicHandler handler, void* context = null)
    nothrow @nogc
{
    PanicHook previous = panicHook;
    panicHook = PanicHook(handler, context);
    return previous;
}

private void rawPanicWrite(String message) nothrow @nogc
{
    enum prefix = "panic: ";
    fwrite(prefix.ptr, 1, prefix.length, cast(FILE*) stderr);
    if (message.length != 0)
        fwrite(message.ptr, 1, message.length, cast(FILE*) stderr);
    enum newline = "\n";
    fwrite(newline.ptr, 1, newline.length, cast(FILE*) stderr);
}

noreturn panic(String message) nothrow @nogc
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

noreturn panicf(string pattern, Args...)(auto ref Args args)
    nothrow @nogc
{
    char[1024] buffer;
    const result = formatBuffer!pattern(buffer[], args);
    panic(buffer[0 .. result.written]);
}

void require(string file = __FILE__, size_t line = __LINE__)(
    bool condition,
    String message,
) nothrow @nogc
{
    if (!condition)
        panicf!"{} ({}:{})"(message, file, line);
}

noreturn unreachableCode(
    string file = __FILE__,
    size_t line = __LINE__,
)() nothrow @nogc
{
    panicf!"unreachable code reached ({}:{})"(file, line);
}
