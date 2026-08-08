module xtb.threading.spin_wait;

nothrow @nogc:

import core.atomic;

/// Gives the processor a short spin-wait hint without yielding to the scheduler.
///
/// This is not an atomic operation or memory fence. Callers must perform any
/// synchronized condition access separately.
void cpuRelax() pure @safe
{
    core.atomic.pause();
}

unittest
{
    cpuRelax();
}
