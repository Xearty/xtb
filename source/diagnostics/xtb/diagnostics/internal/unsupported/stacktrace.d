module xtb.diagnostics.internal.unsupported.stacktrace;

nothrow @nogc:

import xtb.diagnostics.stacktrace;
import xtb.types;

struct StackTraceBackendContext
{
    nothrow @nogc:

    bool available() const pure @safe
    {
        return false;
    }

    static StackTraceBackendContext create(
        const(char)*,
        bool,
    ) pure @safe
    {
        return StackTraceBackendContext.init;
    }
}

StackTrace capture(
    ref StackTraceBackendContext,
    return scope StackFrame[],
    return scope char[],
    u32,
) pure @safe
{
    StackTrace result;
    result.backend_error = true;
    return result;
}
