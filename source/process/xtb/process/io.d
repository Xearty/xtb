module xtb.process.io;

nothrow @nogc:

import xtb.duration : Duration;
import xtb.option : Option, some;

version (XTB_Checked) import xtb.panic : require;
import xtb.types : u64, u8;
import xtb.os.error : OsError, OsErrorKind;
import xtb.os.handle : NativeHandle;
import xtb.os.pipe : PipeReadState, PipeReader, PipeWriteState, PipeWriter,
    close, readSome, writeSome;
import xtb.process.process : ChildProcess, ExitStatus, ProcessError,
    ProcessOperation, WaitState, kill, requestTermination, tryWait;
import xtb.process.internal.time : monotonicNanoseconds, sleepNanoseconds;
import xtb.time : Timeout, TimeoutKind;
import xtb.process.internal.process_backend : NativeActivityHandles,
    NativeProcessWatchState;

version (linux)
    private import backend = xtb.process.internal.linux.process;
else
    private import backend = xtb.process.internal.unsupported.process;

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

    NativeHandle handle;

    @disable this(this);
    @disable ref ProcessWatch opAssign(ProcessWatch source) return;

    void deinit() @system
    {
        backend.closeProcessWatch(handle);
        handle = NativeHandle.init;
    }

    OsError open(scope const(ChildProcess)* child) @system
    {
        const result = backend.openProcessWatch(child.nativeProcessId);
        if (result.error.failed)
            return result.error;
        handle = result.state == NativeProcessWatchState.opened
            ? result.handle : NativeHandle.init;
        return OsError.init;
    }
}

private OsError waitForActivity(
    ChildProcess* child,
    ProcessWatch* watch,
    bool finite,
    u64 remaining,
) @system
{
    NativeActivityHandles handles;
    if (child.stdinPipe !is null)
        handles.stdin = child.stdinPipe.nativeHandle;
    if (child.stdoutPipe !is null)
        handles.stdout = child.stdoutPipe.nativeHandle;
    if (child.stderrPipe !is null)
        handles.stderr = child.stderrPipe.nativeHandle;
    if (watch.handle.valid && child.ownsProcess)
        handles.process = watch.handle;
    return backend.waitForActivity(handles, finite, remaining);
}

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
