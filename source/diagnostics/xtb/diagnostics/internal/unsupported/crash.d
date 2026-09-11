module xtb.diagnostics.internal.unsupported.crash;

nothrow @nogc:

import core.stdc.signal;

import xtb.diagnostics.stacktrace_style;

bool install_crash_signals(bool, scope const StackTraceColors*, sig_atomic_t*) pure @safe
{
    return true;
}

void restore_crash_signals() pure @safe {}
