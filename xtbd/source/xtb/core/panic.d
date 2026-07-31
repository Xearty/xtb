module xtb.core.panic;

import core.stdc.stdlib : abort;
import core.stdc.stdio : FILE, fwrite, stderr;
import xtb.core.types : String;

alias PanicHandler = void function(String message, void* context) nothrow @nogc;

private PanicHandler panicHandler;
private void* panicContext;

void setPanicHandler(PanicHandler handler, void* context = null)
    nothrow @nogc
{
    panicHandler = handler;
    panicContext = context;
}

noreturn panic(String message) nothrow @nogc
{
    if (panicHandler !is null)
        panicHandler(message, panicContext);

    enum prefix = "panic: ";
    fwrite(prefix.ptr, 1, prefix.length, cast(FILE*) stderr);
    if (message.length != 0)
        fwrite(message.ptr, 1, message.length, cast(FILE*) stderr);
    enum newline = "\n";
    fwrite(newline.ptr, 1, newline.length, cast(FILE*) stderr);
    abort();
}

void require(bool condition, String message) nothrow @nogc
{
    if (!condition)
        panic(message);
}
