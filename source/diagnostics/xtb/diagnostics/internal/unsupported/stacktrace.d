module xtb.diagnostics.internal.unsupported.stacktrace;

nothrow @nogc:

import xtb.diagnostics.stacktrace : StackFrame, StackTrace;

struct StackTraceBackendContext
{
nothrow @nogc:

    bool available() const pure @safe
    {
        return false;
    }

    static StackTraceBackendContext create(const(char)*, bool)
    {
        return StackTraceBackendContext.init;
    }
}

StackTrace capture(
    ref StackTraceBackendContext,
    return scope StackFrame[],
    return scope char[],
    uint,
)
{
    StackTrace result;
    result.backendError = true;
    return result;
}
