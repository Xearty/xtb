module xtb.os.linux.signal;

nothrow @nogc:

import core.stdc.config : c_long;
import core.sys.posix.signal : SIG_BLOCK, SIG_SETMASK, SIG_UNBLOCK, sigset_t;
import xtb.os.error : OsError;
import xtb.os.posix.error : lastError;

enum SignalMaskOperation : int
{
    block = SIG_BLOCK,
    unblock = SIG_UNBLOCK,
    setMask = SIG_SETMASK,
}

/// Changes the signal mask of the calling Linux thread.
///
/// This calls `rt_sigprocmask` directly instead of POSIX `sigprocmask`, whose
/// behavior is unspecified in a multithreaded process. `set` and `previous`
/// use the ordinary Linux/POSIX `sigset_t` representation; the kernel consumes
/// the leading native signal-set bytes required by the syscall ABI. `set` may
/// be null to query the current mask, and `previous` may be null when the
/// previous mask is not needed.
OsError signalMask(
    SignalMaskOperation operation,
    scope const sigset_t* set,
    sigset_t* previous,
) @system
{
    const result = syscall(
        rtSigprocmaskSyscallNumber,
        cast(c_long) operation,
        set,
        previous,
        kernelSignalSetSize,
    );
    return result == 0 ? OsError.init : lastError();
}

private extern (C) c_long syscall(c_long number, ...);

version (X86_64)
{
    version (D_X32)
        private enum c_long rtSigprocmaskSyscallNumber = 0x4000_0000 + 14;
    else
        private enum c_long rtSigprocmaskSyscallNumber = 14;
    private enum c_long kernelSignalSetSize = 8;
}
else version (AArch64)
{
    private enum c_long rtSigprocmaskSyscallNumber = 135;
    private enum c_long kernelSignalSetSize = 8;
}
else
{
    static assert(false, "Linux signal-mask syscall is unsupported on this architecture");
}

unittest
{
    import core.sys.posix.signal : SIGPIPE, sigaddset, sigemptyset, sigismember;

    sigset_t before;
    assert(signalMask(SignalMaskOperation.setMask, null, &before).succeeded);

    sigset_t blocked;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGPIPE);

    sigset_t previous;
    assert(signalMask(SignalMaskOperation.block, &blocked, &previous).succeeded);
    assert(sigismember(&previous, SIGPIPE) == sigismember(&before, SIGPIPE));

    sigset_t current;
    assert(signalMask(SignalMaskOperation.setMask, null, &current).succeeded);
    assert(sigismember(&current, SIGPIPE) == 1);

    assert(signalMask(SignalMaskOperation.setMask, &previous, null).succeeded);
    assert(signalMask(SignalMaskOperation.setMask, null, &current).succeeded);
    assert(sigismember(&current, SIGPIPE) == sigismember(&before, SIGPIPE));
}
