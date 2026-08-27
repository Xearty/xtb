module xtb.diagnostics.internal.unsupported.crash;

nothrow @nogc:

import core.stdc.signal : sig_atomic_t;
import xtb.diagnostics.stacktrace_style : StackTraceColors;

bool installCrashSignals(
    bool,
    scope const StackTraceColors*,
    sig_atomic_t*,
)
{
    return true;
}

void restoreCrashSignals()
{
}
