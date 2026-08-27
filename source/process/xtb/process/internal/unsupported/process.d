module xtb.process.internal.unsupported.process;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.process.internal.process_backend : NativeActivityDescriptors,
    NativeProcessWatchResult, NativeProcessWatchState, NativeSignal,
    NativeSpawnOptions, NativeWaitResult, NativeWaitState, NativeWatchWaitResult;
import xtb.types : u64;

package(xtb.process) const(char)** currentEnvironment() pure @safe
{
    return null;
}

package(xtb.process) OsError validateChildReapingPolicy() pure @safe
{
    return unsupported();
}

package(xtb.process) struct NativeSpawn
{
nothrow @nogc:

    @disable this(this);
    @disable ref NativeSpawn opAssign(NativeSpawn source) return;

    void deinit() pure @safe
    {
    }

    OsError prepare(scope const(NativeSpawnOptions)) pure @safe
    {
        return unsupported();
    }

    OsError execute(const(char)*, const(char)**, const(char)**, int*) pure @safe
    {
        return unsupported();
    }
}

package(xtb.process) NativeWaitResult waitProcess(int, bool) pure @safe
{
    return NativeWaitResult(unsupported(), NativeWaitState.running, 0, false);
}

package(xtb.process) NativeProcessWatchResult openProcessWatch(int) pure @safe
{
    return NativeProcessWatchResult(
        unsupported(),
        NativeProcessWatchState.unavailable,
        -1,
    );
}

package(xtb.process) void closeProcessWatch(int) pure @safe
{
}

package(xtb.process) NativeWatchWaitResult waitProcessWatch(int, u64) pure @safe
{
    return NativeWatchWaitResult(unsupported(), false);
}

package(xtb.process) OsError waitForActivity(
    NativeActivityDescriptors,
    bool,
    u64,
) pure @safe
{
    return unsupported();
}

package(xtb.process) OsError signalProcess(int, bool, NativeSignal) pure @safe
{
    return unsupported();
}
