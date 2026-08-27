module xtb.process.internal.unsupported.process;

nothrow @nogc:

import xtb.os.error : OsError, unsupported;
import xtb.os.handle : NativeHandle;
import xtb.process.internal.process_backend : NativeActivityHandles,
    NativeProcessId, NativeProcessWatchResult, NativeProcessWatchState,
    NativeSignal, NativeSpawnOptions, NativeWaitResult, NativeWaitState,
    NativeWatchWaitResult;
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

    OsError execute(
        const(char)*,
        const(char)**,
        const(char)**,
        NativeProcessId*,
    ) pure @safe
    {
        return unsupported();
    }
}

package(xtb.process) NativeWaitResult waitProcess(
    NativeProcessId,
    bool,
) pure @safe
{
    return NativeWaitResult(unsupported(), NativeWaitState.running, 0, false);
}

package(xtb.process) NativeProcessWatchResult openProcessWatch(
    NativeProcessId,
) pure @safe
{
    return NativeProcessWatchResult(
        unsupported(),
        NativeProcessWatchState.unavailable,
        NativeHandle.init,
    );
}

package(xtb.process) void closeProcessWatch(NativeHandle) pure @safe
{
}

package(xtb.process) NativeWatchWaitResult waitProcessWatch(
    NativeHandle,
    u64,
) pure @safe
{
    return NativeWatchWaitResult(unsupported(), false);
}

package(xtb.process) OsError waitForActivity(
    NativeActivityHandles,
    bool,
    u64,
) pure @safe
{
    return unsupported();
}

package(xtb.process) OsError signalProcess(
    NativeProcessId,
    bool,
    NativeSignal,
) pure @safe
{
    return unsupported();
}
