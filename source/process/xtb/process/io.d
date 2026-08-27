module xtb.process.io;

nothrow @nogc:

import xtb.duration : Duration;
import xtb.option : Option, some;

version (XTB_Checked) import xtb.panic : require;
import xtb.types : u64, u8;
import xtb.os.error : OsError, OsErrorKind, lastError, unsupported;
import xtb.os.pipe : PipeReadState, PipeReader, PipeWriteState, PipeWriter,
    close, readSome, writeSome;
import xtb.process.process : ChildProcess, ExitStatus, ProcessError,
    ProcessOperation, WaitState, kill, requestTermination, tryWait;
import xtb.os.time : Timeout, TimeoutKind, monotonicNanoseconds,
    sleepNanoseconds;

struct CaptureBuffer
{
nothrow @nogc:

    u8[] storage;
    size_t length;
    bool truncated;

    u8[] bytes() return @system
    {
        version (XTB_Checked)
            require(length <= storage.length, "invalid CaptureBuffer length");
        return storage[0 .. length];
    }

    const(u8)[] bytes() const return @system
    {
        version (XTB_Checked)
            require(length <= storage.length, "invalid CaptureBuffer length");
        return storage[0 .. length];
    }
}

enum TimeoutAction : ubyte
{
    leaveRunning,
    requestThenKill,
    kill,
}

enum CommunicateState : ubyte
{
    completed,
    timedOutRunning,
    timedOutTerminated,
}

struct CommunicateOptions
{
    Timeout timeout;
    TimeoutAction timeoutAction;
    Duration terminationGrace;
}

CommunicateOptions withTimeout(
    CommunicateOptions options,
    Duration duration,
) pure @safe
{
    options.timeout = Timeout.after(duration);
    return options;
}

CommunicateOptions withoutTimeout(CommunicateOptions options) pure @safe
{
    options.timeout = Timeout.infinite;
    return options;
}

CommunicateOptions withTimeoutAction(
    CommunicateOptions options,
    TimeoutAction action,
) pure @safe
{
    options.timeoutAction = action;
    return options;
}

CommunicateOptions withTerminationGrace(
    CommunicateOptions options,
    Duration duration,
) pure @safe
{
    options.terminationGrace = duration;
    return options;
}

struct CommunicateResult
{
    ProcessError error;
    CommunicateState state;
    size_t inputWritten;
    Option!ExitStatus exitStatus;
}

CommunicateResult communicate(
    ChildProcess* child,
    scope const(u8)[] input,
    CaptureBuffer* stdoutCapture,
    CaptureBuffer* stderrCapture,
    scope const(CommunicateOptions) options,
) @system
{
    version (XTB_Checked)
        require(child !is null && child.ownsProcess,
            "invalid ChildProcess for communicate");

    const validationError = validateCommunication(
        child,
        input,
        stdoutCapture,
        stderrCapture,
        options,
    );
    if (validationError.failed)
        return communicationFailure(validationError, 0);

    Deadline deadline;
    OsError error = makeDeadline(options.timeout, &deadline);
    if (error.failed)
        return communicationFailure(error, 0);

    ProcessWatch watch;
    scope (exit)
        watch.deinit();
    error = watch.open(child);
    if (error.failed)
        return communicationFailure(error, 0);

    size_t inputWritten;
    Option!ExitStatus exitStatus;
    for (;;)
    {
        error = pumpInput(child.stdinPipe, input, &inputWritten);
        if (error.failed)
            return communicationFailure(error, inputWritten);
        error = pumpOutput(child.stdoutPipe, stdoutCapture);
        if (error.failed)
            return communicationFailure(error, inputWritten);
        error = pumpOutput(child.stderrPipe, stderrCapture);
        if (error.failed)
            return communicationFailure(error, inputWritten);

        error = observeExit(child, &exitStatus);
        if (error.failed)
            return communicationFailure(error, inputWritten);
        if (exitStatus.isSome && child.stdinPipe !is null)
        {
            error = close(child.stdinPipe);
            if (error.failed)
                return communicationFailure(error, inputWritten);
        }

        if (communicationFinished(child, inputWritten, input.length))
            return CommunicateResult(
                ProcessError.init,
                CommunicateState.completed,
                inputWritten,
                exitStatus,
            );

        bool expired;
        u64 remaining;
        error = deadline.remaining(&remaining, &expired);
        if (error.failed)
            return communicationFailure(error, inputWritten);
        if (expired)
            return finishTimeout(
                child,
                inputWritten,
                stdoutCapture,
                stderrCapture,
                options,
                &watch,
                exitStatus,
            );

        error = waitForActivity(child, &watch, deadline.finite, remaining);
        if (error.failed)
            return communicationFailure(error, inputWritten);
    }
}

private OsError validateCommunication(
    scope const(ChildProcess)* child,
    scope const(u8)[] input,
    scope const(CaptureBuffer)* stdoutCapture,
    scope const(CaptureBuffer)* stderrCapture,
    scope const(CommunicateOptions) options,
) @system
{
    if (cast(u8) options.timeout.kind > cast(u8) TimeoutKind.finite ||
        cast(u8) options.timeoutAction > cast(u8) TimeoutAction.kill ||
        (stdoutCapture !is null &&
            stdoutCapture.length > stdoutCapture.storage.length) ||
        (stderrCapture !is null &&
            stderrCapture.length > stderrCapture.storage.length) ||
        (input.length != 0 && !child.hasStdinPipe) ||
        (stdoutCapture !is null && !child.hasStdoutPipe) ||
        (stderrCapture !is null && !child.hasStderrPipe) ||
        (stdoutCapture !is null && stdoutCapture is stderrCapture) ||
        (stdoutCapture !is null &&
            slicesOverlap(input, stdoutCapture.storage)) ||
        (stderrCapture !is null &&
            slicesOverlap(input, stderrCapture.storage)) ||
        (stdoutCapture !is null && stderrCapture !is null &&
            slicesOverlap(stdoutCapture.storage, stderrCapture.storage)))
        return OsError(OsErrorKind.invalidArgument, 0);
    return OsError.init;
}

private OsError pumpInput(
    PipeWriter* writer,
    scope const(u8)[] input,
    size_t* written,
) @system
{
    version (XTB_Checked)
        require(written !is null && *written <= input.length,
            "invalid communicate input progress");
    if (writer is null)
        return OsError.init;
    if (*written == input.length)
        return close(writer);

    while (*written != input.length)
    {
        const result = writeSome(writer, input[*written .. $]);
        if (result.error.failed)
            return result.error;
        if (result.state == PipeWriteState.peerClosed)
            return close(writer);
        if (result.state == PipeWriteState.wouldBlock)
            return OsError.init;
        *written += result.transferred;
    }
    return close(writer);
}

private OsError pumpOutput(
    PipeReader* reader,
    CaptureBuffer* capture,
) @system
{
    if (reader is null)
        return OsError.init;

    u8[4096] discarded;
    for (;;)
    {
        u8[] destination;
        bool discarding;
        if (capture is null || capture.length == capture.storage.length)
        {
            destination = discarded[];
            discarding = true;
        }
        else
            destination = capture.storage[capture.length .. $];

        const result = readSome(reader, destination);
        if (result.error.failed)
            return result.error;
        if (result.state == PipeReadState.endOfFile)
            return close(reader);
        if (result.state == PipeReadState.wouldBlock)
            return OsError.init;
        if (discarding)
        {
            if (capture !is null && result.transferred != 0)
                capture.truncated = true;
        }
        else
            capture.length += result.transferred;
    }
}

private OsError observeExit(
    ChildProcess* child,
    Option!ExitStatus* exitStatus,
) @system
{
    version (XTB_Checked)
        require(exitStatus !is null, "communicate exit status pointer is null");
    if (!child.ownsProcess)
        return OsError.init;
    auto result = tryWait(child);
    if (result.error.failed)
        return result.error.os;
    if (result.state == WaitState.exited)
        *exitStatus = some(result.status);
    return OsError.init;
}

private bool communicationFinished(
    scope const(ChildProcess)* child,
    size_t written,
    size_t inputLength,
) @system
{
    return !child.ownsProcess && !child.hasStdinPipe &&
        !child.hasStdoutPipe && !child.hasStderrPipe &&
        written <= inputLength;
}

private CommunicateResult finishTimeout(
    ChildProcess* child,
    size_t inputWritten,
    CaptureBuffer* stdoutCapture,
    CaptureBuffer* stderrCapture,
    scope const(CommunicateOptions) options,
    ProcessWatch* watch,
    Option!ExitStatus exitStatus,
) @system
{
    if (options.timeoutAction == TimeoutAction.leaveRunning)
        return CommunicateResult(
            ProcessError.init,
            CommunicateState.timedOutRunning,
            inputWritten,
            exitStatus,
        );

    OsError error;
    if (child.stdinPipe !is null)
    {
        error = close(child.stdinPipe);
        if (error.failed)
            return communicationFailure(error, inputWritten);
    }

    if (!child.ownsProcess)
    {
        error = closeRemainingOutputs(child);
        if (error.failed)
            return communicationFailure(error, inputWritten);
        return CommunicateResult(
            ProcessError.init,
            CommunicateState.timedOutTerminated,
            inputWritten,
            exitStatus,
        );
    }

    bool forceful = options.timeoutAction == TimeoutAction.kill;
    ProcessError signalError = forceful
        ? kill(child) : requestTermination(child);
    if (signalError.failed && signalError.os.kind != OsErrorKind.notFound)
        return communicationFailure(signalError.os, inputWritten);

    Deadline grace;
    if (!forceful)
    {
        error = makeDeadline(Timeout.after(options.terminationGrace), &grace);
        if (error.failed)
            return communicationFailure(error, inputWritten);
    }

    while (child.ownsProcess)
    {
        error = pumpOutput(child.stdoutPipe, stdoutCapture);
        if (error.failed)
            return communicationFailure(error, inputWritten);
        error = pumpOutput(child.stderrPipe, stderrCapture);
        if (error.failed)
            return communicationFailure(error, inputWritten);
        error = observeExit(child, &exitStatus);
        if (error.failed)
            return communicationFailure(error, inputWritten);
        if (!child.ownsProcess)
            break;

        bool expired;
        u64 remaining;
        if (forceful)
        {
            remaining = 0;
            expired = false;
        }
        else
        {
            error = grace.remaining(&remaining, &expired);
            if (error.failed)
                return communicationFailure(error, inputWritten);
            if (expired)
            {
                signalError = kill(child);
                if (signalError.failed &&
                    signalError.os.kind != OsErrorKind.notFound)
                    return communicationFailure(signalError.os, inputWritten);
                forceful = true;
                continue;
            }
        }

        error = waitForActivity(child, watch, !forceful, remaining);
        if (error.failed)
            return communicationFailure(error, inputWritten);
    }

    error = pumpOutput(child.stdoutPipe, stdoutCapture);
    if (error.failed)
        return communicationFailure(error, inputWritten);
    error = pumpOutput(child.stderrPipe, stderrCapture);
    if (error.failed)
        return communicationFailure(error, inputWritten);
    error = closeRemainingOutputs(child);
    if (error.failed)
        return communicationFailure(error, inputWritten);
    return CommunicateResult(
        ProcessError.init,
        CommunicateState.timedOutTerminated,
        inputWritten,
        exitStatus,
    );
}

private OsError closeRemainingOutputs(ChildProcess* child) @system
{
    if (child.stdoutPipe !is null)
    {
        const error = close(child.stdoutPipe);
        if (error.failed)
            return error;
    }
    if (child.stderrPipe !is null)
        return close(child.stderrPipe);
    return OsError.init;
}

private bool slicesOverlap(
    scope const(u8)[] left,
    scope const(u8)[] right,
) pure @system
{
    if (left.length == 0 || right.length == 0)
        return false;
    const leftAddress = cast(size_t) left.ptr;
    const rightAddress = cast(size_t) right.ptr;
    return leftAddress <= rightAddress
        ? rightAddress - leftAddress < left.length : leftAddress - rightAddress < right.length;
}

private CommunicateResult communicationFailure(
    OsError error,
    size_t inputWritten,
) pure @safe
{
    return CommunicateResult(
        ProcessError(error, ProcessOperation.communicate),
        CommunicateState.completed,
        inputWritten,
        Option!ExitStatus.init,
    );
}

private struct Deadline
{
nothrow @nogc:

    bool finite;
    u64 value;

    OsError remaining(u64* output, bool* expired) const @system
    {
        version (XTB_Checked)
            require(output !is null && expired !is null,
                "deadline output pointer is null");
        if (!finite)
        {
            *output = u64.max;
            *expired = false;
            return OsError.init;
        }
        u64 now;
        const error = monotonicNanoseconds(&now);
        if (error.failed)
            return error;
        *expired = now >= value;
        *output = *expired ? 0 : value - now;
        return OsError.init;
    }
}

private OsError makeDeadline(Timeout timeout, Deadline* output) @system
{
    version (XTB_Checked)
        require(output !is null, "deadline pointer is null");
    *output = Deadline.init;
    if (timeout.isInfinite)
        return OsError.init;

    u64 now;
    const error = monotonicNanoseconds(&now);
    if (error.failed)
        return error;
    const duration = timeout.isImmediate
        ? 0 : timeout.duration.totalNanoseconds;
    output.finite = true;
    output.value = duration > u64.max - now ? u64.max : now + duration;
    return OsError.init;
}

private struct ProcessWatch
{
nothrow @nogc:

    int descriptor = -1;

    @disable this(this);
    @disable ref ProcessWatch opAssign(ProcessWatch source) return;

    void deinit() @system
    {
        version (linux)
        {
            if (descriptor >= 0)
            {
                import core.sys.posix.unistd : nativeClose = close;

                cast(void) nativeClose(descriptor);
                descriptor = -1;
            }
        }
        else
            descriptor = -1;
    }

    OsError open(scope const(ChildProcess)* child) @system
    {
        version (linux)
        {
            import core.stdc.errno : EINVAL, ENOSYS, EPERM;

            descriptor = nativePidfdOpen(cast(int) child.id.value, 0);
            if (descriptor >= 0)
                return OsError.init;
            const error = lastError();
            if (error.nativeCode == ENOSYS || error.nativeCode == EINVAL ||
                error.nativeCode == EPERM || error.kind == OsErrorKind.notFound)
                return OsError.init;
            return error;
        }
        else
            return unsupported();
    }
}

private OsError waitForActivity(
    ChildProcess* child,
    ProcessWatch* watch,
    bool finite,
    u64 remaining,
) @system
{
    version (linux)
    {
        import core.stdc.errno : EINTR, errno;
        import core.sys.posix.poll : POLLIN, POLLNVAL, POLLOUT, pollfd;
        import core.sys.posix.time : timespec;

        pollfd[4] items;
        size_t count;
        if (child.stdinPipe !is null)
        {
            items[count].fd = child.stdinPipe.nativeDescriptor;
            items[count].events = POLLOUT;
            ++count;
        }
        if (child.stdoutPipe !is null)
        {
            items[count].fd = child.stdoutPipe.nativeDescriptor;
            items[count].events = POLLIN;
            ++count;
        }
        if (child.stderrPipe !is null)
        {
            items[count].fd = child.stderrPipe.nativeDescriptor;
            items[count].events = POLLIN;
            ++count;
        }
        if (watch.descriptor >= 0 && child.ownsProcess)
        {
            items[count].fd = watch.descriptor;
            items[count].events = POLLIN;
            ++count;
        }

        enum u64 fallbackObservation = 64_000_000;
        u64 wait = remaining;
        if (watch.descriptor < 0 && (!finite || wait > fallbackObservation))
            wait = fallbackObservation;

        timespec timeout;
        const(timespec)* timeoutPointer;
        if (finite || watch.descriptor < 0)
        {
            timeout.tv_sec = cast(typeof(timeout.tv_sec))(
                wait / 1_000_000_000UL
            );
            timeout.tv_nsec = cast(typeof(timeout.tv_nsec))(
                wait % 1_000_000_000UL
            );
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
    else
    {
        cast(void) child;
        cast(void) watch;
        cast(void) finite;
        cast(void) remaining;
        return unsupported();
    }
}

version (linux) private extern (C) pragma(mangle, "pidfd_open")
int nativePidfdOpen(int processId, uint flags);

version (linux) private extern (C) pragma(mangle, "ppoll")
int nativePpoll(void* descriptors, size_t count, const(void)* timeout,
    const(void)* signalMask);

unittest
{
    import xtb.duration : milliseconds;

    u8[8] storage;
    CaptureBuffer capture = CaptureBuffer(storage[]);
    assert(capture.bytes.length == 0 && !capture.truncated);

    const options = CommunicateOptions.init
        .withTimeout(milliseconds(10))
        .withTimeoutAction(TimeoutAction.requestThenKill)
        .withTerminationGrace(milliseconds(20));
    assert(options.timeout.isFinite);
    assert(options.timeoutAction == TimeoutAction.requestThenKill);
    assert(options.terminationGrace == milliseconds(20));
    assert(options.withoutTimeout.timeout.isInfinite);
}
