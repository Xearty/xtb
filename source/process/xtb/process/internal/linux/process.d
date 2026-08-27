module xtb.process.internal.linux.process;

nothrow @nogc:

import core.stdc.errno : EINVAL, EINTR, ENOSYS, EPERM, errno;
import core.stdc.signal : SIG_IGN;
import core.sys.posix.fcntl : O_RDONLY, O_WRONLY, fcntl;
import core.sys.posix.poll : POLLIN, POLLNVAL, POLLOUT, pollfd;
import core.sys.posix.signal : SA_NOCLDWAIT, SIGCHLD, SIGKILL, SIGTERM,
    kill, sigaction, sigaction_t, sigemptyset, sigset_t;
import core.sys.posix.spawn : POSIX_SPAWN_SETPGROUP, POSIX_SPAWN_SETSIGMASK,
    posix_spawn, posix_spawn_file_actions_adddup2,
    posix_spawn_file_actions_addopen, posix_spawn_file_actions_destroy,
    posix_spawn_file_actions_init, posix_spawn_file_actions_t,
    posix_spawnattr_destroy, posix_spawnattr_init, posix_spawnattr_setflags,
    posix_spawnattr_setpgroup, posix_spawnattr_setsigmask, posix_spawnattr_t;
import core.sys.posix.sys.types : pid_t;
import core.sys.posix.sys.wait : WNOHANG, waitpid;
import core.sys.posix.time : timespec;
import core.sys.posix.unistd : nativeClose = close, environ;
import xtb.os.error : OsError, OsErrorKind;
import xtb.os.posix.error : fromErrno, lastError;
import xtb.os.handle : NativeHandle;
import xtb.os.posix.handle : fileDescriptor, fromFileDescriptor;
import xtb.process.internal.process_backend : NativeActivityHandles,
    NativeProcessId, NativeProcessWatchResult, NativeProcessWatchState,
    NativeRoute, NativeRouteKind, NativeSignal, NativeSpawnOptions,
    NativeWaitResult, NativeWaitState, NativeWatchWaitResult;
import xtb.types : u32, u64;

package(xtb.process) const(char)** currentEnvironment() @system
{
    return cast(const(char)**) environ;
}

package(xtb.process) OsError validateChildReapingPolicy() @system
{
    sigaction_t current;
    if (sigaction(SIGCHLD, null, &current) != 0)
        return lastError();
    if (current.sa_handler is SIG_IGN || (current.sa_flags & SA_NOCLDWAIT) != 0)
        return OsError(OsErrorKind.invalidArgument, 0);
    return OsError.init;
}

package(xtb.process) struct NativeSpawn
{
nothrow @nogc:

    private posix_spawn_file_actions_t actions;
    private posix_spawnattr_t attributes;
    private bool actionsActive;
    private bool attributesActive;
    private int[3] stagedDescriptors = [-1, -1, -1];

    @disable this(this);
    @disable ref NativeSpawn opAssign(NativeSpawn source) return;

    void deinit() @system
    {
        foreach (ref descriptor; stagedDescriptors)
        {
            if (descriptor >= 0)
            {
                cast(void) nativeClose(descriptor);
                descriptor = -1;
            }
        }
        if (actionsActive)
        {
            cast(void) posix_spawn_file_actions_destroy(&actions);
            actionsActive = false;
        }
        if (attributesActive)
        {
            cast(void) posix_spawnattr_destroy(&attributes);
            attributesActive = false;
        }
    }

    OsError prepare(scope const(NativeSpawnOptions) options) @system
    {
        int code = posix_spawn_file_actions_init(&actions);
        if (code != 0)
            return fromErrno(code);
        actionsActive = true;
        code = posix_spawnattr_init(&attributes);
        if (code != 0)
            return fromErrno(code);
        attributesActive = true;

        short flags;
        if (options.clearSignalMask)
        {
            sigset_t emptyMask;
            sigemptyset(&emptyMask);
            code = posix_spawnattr_setsigmask(&attributes, &emptyMask);
            if (code != 0)
                return fromErrno(code);
            flags |= POSIX_SPAWN_SETSIGMASK;
        }
        if (options.isolatedTree)
        {
            code = posix_spawnattr_setpgroup(&attributes, 0);
            if (code != 0)
                return fromErrno(code);
            flags |= POSIX_SPAWN_SETPGROUP;
        }
        code = posix_spawnattr_setflags(&attributes, flags);
        if (code != 0)
            return fromErrno(code);

        code = prepareInput(options.stdin);
        if (code != 0)
            return fromErrno(code);
        code = prepareOutput(options.stdout, 1, 1);
        if (code != 0)
            return fromErrno(code);
        code = prepareError(options.stderr);
        if (code != 0)
            return fromErrno(code);

        if (options.workingDirectory !is null)
        {
            code = addChdir(&actions, options.workingDirectory);
            if (code != 0)
                return fromErrno(code);
        }
        code = addCloseFrom(&actions, 3);
        return code == 0 ? OsError.init : fromErrno(code);
    }

    OsError execute(
        const(char)* executable,
        const(char)** argv,
        const(char)** environment,
        NativeProcessId* output,
    ) @system
    {
        pid_t processId;
        const code = posix_spawn(
            &processId,
            executable,
            &actions,
            &attributes,
            argv,
            environment,
        );
        if (code != 0)
            return fromErrno(code);
        *output = fromProcessId(processId);
        return OsError.init;
    }

    private int prepareInput(NativeRoute route) @system
    {
        final switch (route.kind)
        {
            case NativeRouteKind.inherited:
                return 0;
            case NativeRouteKind.nullDevice:
                return posix_spawn_file_actions_addopen(
                    &actions, 0, "/dev/null".ptr, O_RDONLY, 0,
                );
            case NativeRouteKind.handle:
                return addDescriptor(toDescriptor(route.handle), 0, 0);
            case NativeRouteKind.mergeWithStdout:
                return EINVAL;
        }
    }

    private int prepareOutput(NativeRoute route, int target, size_t index) @system
    {
        final switch (route.kind)
        {
            case NativeRouteKind.inherited:
                return 0;
            case NativeRouteKind.nullDevice:
                return posix_spawn_file_actions_addopen(
                    &actions, target, "/dev/null".ptr, O_WRONLY, 0,
                );
            case NativeRouteKind.handle:
                return addDescriptor(toDescriptor(route.handle), target, index);
            case NativeRouteKind.mergeWithStdout:
                return EINVAL;
        }
    }

    private int prepareError(NativeRoute route) @system
    {
        if (route.kind == NativeRouteKind.mergeWithStdout)
            return posix_spawn_file_actions_adddup2(&actions, 1, 2);
        return prepareOutput(route, 2, 2);
    }

    private int addDescriptor(int descriptor, int target, size_t index) @system
    {
        enum F_DUPFD_CLOEXEC = 1030;
        const staged = fcntl(descriptor, F_DUPFD_CLOEXEC, 3);
        if (staged < 0)
            return lastError().nativeCode;
        stagedDescriptors[index] = staged;
        return posix_spawn_file_actions_adddup2(&actions, staged, target);
    }
}

private extern (C) pragma(mangle, "posix_spawn_file_actions_addchdir_np")
int addChdir(void* actions, const(char)* path);

private extern (C) pragma(mangle, "posix_spawn_file_actions_addclosefrom_np")
int addCloseFrom(void* actions, int from);

package(xtb.process) NativeWaitResult waitProcess(
    NativeProcessId processId,
    bool nonBlocking,
) @system
{
    int nativeStatus;
    int result;
    do
        result = waitpid(toProcessId(processId), &nativeStatus, nonBlocking ? WNOHANG : 0);
    while (result < 0 && errno == EINTR);
    if (result < 0)
        return NativeWaitResult(lastError(), NativeWaitState.running, 0, false);
    if (result == 0)
        return NativeWaitResult(OsError.init, NativeWaitState.running, 0, false);

    if (nativeExited(nativeStatus))
        return NativeWaitResult(
            OsError.init,
            NativeWaitState.exited,
            cast(u32) nativeExitCode(nativeStatus),
            false,
        );
    if (nativeSignaled(nativeStatus))
        return NativeWaitResult(
            OsError.init,
            NativeWaitState.signaled,
            cast(u32) nativeTerminationSignal(nativeStatus),
            (nativeStatus & 0x80) != 0,
        );
    return NativeWaitResult(
        OsError(OsErrorKind.system, 0),
        NativeWaitState.running,
        0,
        false,
    );
}

private bool nativeExited(int status) pure @safe
{
    return (status & 0x7f) == 0;
}

private bool nativeSignaled(int status) pure @safe
{
    const signal = status & 0x7f;
    return signal != 0 && signal != 0x7f;
}

private int nativeExitCode(int status) pure @safe
{
    return (status >> 8) & 0xff;
}

private int nativeTerminationSignal(int status) pure @safe
{
    return status & 0x7f;
}

package(xtb.process) NativeProcessWatchResult openProcessWatch(
    NativeProcessId processId,
) @system
{
    const descriptor = nativePidfdOpen(cast(int) processId.nativeValue, 0);
    if (descriptor >= 0)
        return NativeProcessWatchResult(
            OsError.init,
            NativeProcessWatchState.opened,
            fromDescriptor(descriptor),
        );
    const error = lastError();
    if (error.nativeCode == ENOSYS || error.nativeCode == EINVAL ||
        error.nativeCode == EPERM || error.kind == OsErrorKind.notFound)
        return NativeProcessWatchResult(
            OsError.init,
            NativeProcessWatchState.unavailable,
            NativeHandle.init,
        );
    return NativeProcessWatchResult(
        error,
        NativeProcessWatchState.unavailable,
        NativeHandle.init,
    );
}

package(xtb.process) void closeProcessWatch(NativeHandle handle) @system
{
    if (handle.valid)
        cast(void) nativeClose(toDescriptor(handle));
}

package(xtb.process) NativeWatchWaitResult waitProcessWatch(
    NativeHandle handle,
    u64 timeoutNanoseconds,
) @system
{
    pollfd event;
    event.fd = toDescriptor(handle);
    event.events = POLLIN;

    timespec timeout;
    timeout.tv_sec = cast(typeof(timeout.tv_sec))(
        timeoutNanoseconds / 1_000_000_000UL
    );
    timeout.tv_nsec = cast(typeof(timeout.tv_nsec))(
        timeoutNanoseconds % 1_000_000_000UL
    );
    const result = nativePpoll(&event, 1, &timeout, null);
    if (result > 0)
        return NativeWatchWaitResult(OsError.init, true);
    if (result == 0 || errno == EINTR)
        return NativeWatchWaitResult(OsError.init, false);
    return NativeWatchWaitResult(lastError(), false);
}

package(xtb.process) OsError waitForActivity(
    NativeActivityHandles handles,
    bool finite,
    u64 remaining,
) @system
{
    pollfd[4] items;
    size_t count;
    if (handles.stdin.valid)
    {
        items[count].fd = toDescriptor(handles.stdin);
        items[count].events = POLLOUT;
        ++count;
    }
    if (handles.stdout.valid)
    {
        items[count].fd = toDescriptor(handles.stdout);
        items[count].events = POLLIN;
        ++count;
    }
    if (handles.stderr.valid)
    {
        items[count].fd = toDescriptor(handles.stderr);
        items[count].events = POLLIN;
        ++count;
    }
    if (handles.process.valid)
    {
        items[count].fd = toDescriptor(handles.process);
        items[count].events = POLLIN;
        ++count;
    }

    enum u64 fallbackObservation = 64_000_000;
    u64 wait = remaining;
    if (!handles.process.valid && (!finite || wait > fallbackObservation))
        wait = fallbackObservation;

    timespec timeout;
    const(timespec)* timeoutPointer;
    if (finite || !handles.process.valid)
    {
        timeout.tv_sec = cast(typeof(timeout.tv_sec))(wait / 1_000_000_000UL);
        timeout.tv_nsec = cast(typeof(timeout.tv_nsec))(wait % 1_000_000_000UL);
        timeoutPointer = &timeout;
    }
    const result = nativePpoll(items.ptr, count, timeoutPointer, null);
    if (result < 0)
        return errno == EINTR ? OsError.init : lastError();
    foreach (item; items[0 .. count])
    {
        if ((item.revents & POLLNVAL) != 0)
            return OsError(OsErrorKind.system, 0);
    }
    return OsError.init;
}

package(xtb.process) OsError signalProcess(
    NativeProcessId processId,
    bool processGroup,
    NativeSignal signal,
) @system
{
    const nativeId = toProcessId(processId);
    const target = processGroup ? -nativeId : nativeId;
    int nativeSignal;
    final switch (signal)
    {
        case NativeSignal.terminate:
            nativeSignal = SIGTERM;
            break;
        case NativeSignal.kill:
            nativeSignal = SIGKILL;
            break;
    }
    return kill(target, nativeSignal) == 0 ? OsError.init : lastError();
}

private NativeHandle fromDescriptor(int descriptor) pure @safe
{
    return fromFileDescriptor(descriptor);
}

private int toDescriptor(NativeHandle handle) pure @safe
{
    return fileDescriptor(handle);
}

private NativeProcessId fromProcessId(pid_t processId) pure @safe
{
    return NativeProcessId.fromNativeValue(cast(ulong) processId);
}

private pid_t toProcessId(NativeProcessId processId) pure @safe
{
    return cast(pid_t) processId.nativeValue;
}

private extern (C) pragma(mangle, "pidfd_open")
int nativePidfdOpen(int processId, uint flags);

private extern (C) pragma(mangle, "ppoll")
int nativePpoll(void* descriptors, size_t count, const(void)* timeout,
    const(void)* signalMask);
