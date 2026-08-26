module xtb.os.pipeline;

nothrow @nogc:

import xtb.lifetime : moveAssign, moveEmplace;
import xtb.containers.array;
import xtb.memory : Allocator;
import xtb.option : Option, some;

version (XTB_Checked) import xtb.panic : require;
import xtb.string;
import xtb.types : u8;
import xtb.os.error : OsError, OsErrorKind;
import xtb.os.pipe : Pipe, PipeOptions, PipeReader, PipeWriter, close,
    createPipe;
import xtb.os.process : ChildProcess, Command, ErrorRoute, ExitStatus,
    InputRoute, OutputRoute, ProcessError, ProcessIsolation, ProcessOperation,
    ProcessId, SignalMaskPolicy, SpawnOptions, WaitState, childKill = kill,
    childRequestTermination = requestTermination, rollbackSpawnedProcess, spawn,
    childTryWait = tryWait, validate, childWait = wait;

struct PipelineStage
{
    Command command;
    Option!ErrorRoute stderrOverride;
}

PipelineStage withStderr(PipelineStage stage, ErrorRoute route) @system
{
    stage.stderrOverride = some(route);
    return stage;
}

PipelineStage withDefaultStderr(PipelineStage stage) @system
{
    stage.stderrOverride.reset();
    return stage;
}

enum PipelineSuccess : ubyte
{
    lastStage,
    everyStage,
}

struct PipelineOptions
{
    InputRoute stdin;
    OutputRoute stdout;
    ErrorRoute stderr;
    PipelineSuccess success;
    ProcessIsolation isolation;
    SignalMaskPolicy signalMask;
}

PipelineOptions withStdin(PipelineOptions options, InputRoute route) pure @safe
{
    options.stdin = route;
    return options;
}

PipelineOptions withStdout(PipelineOptions options, OutputRoute route) pure @safe
{
    options.stdout = route;
    return options;
}

PipelineOptions withStderr(PipelineOptions options, ErrorRoute route) pure @safe
{
    options.stderr = route;
    return options;
}

PipelineOptions withSuccessPolicy(
    PipelineOptions options,
    PipelineSuccess success,
) pure @safe
{
    options.success = success;
    return options;
}

PipelineOptions withIsolation(
    PipelineOptions options,
    ProcessIsolation isolation,
) pure @safe
{
    options.isolation = isolation;
    return options;
}

PipelineOptions withSignalMask(
    PipelineOptions options,
    SignalMaskPolicy policy,
) pure @safe
{
    options.signalMask = policy;
    return options;
}

enum PipelineWaitState : ubyte
{
    running,
    completed,
}

struct PipelineWaitResult
{
    ProcessError error;
    PipelineWaitState state;
    size_t runningStages;
}

/// Owns the child handles, statuses, and parent-side pipes for a pipeline.
///
/// Stage lifecycle is explicit: all live children must be reaped with
/// `waitPipeline`, `terminatePipelineAndWait`, `killPipelineAndWait`, or an
/// equivalent operation before `deinit`. Generic deinitialization only releases
/// remaining local pipe and storage state.
struct Pipeline
{
nothrow @nogc:

    private Array!ChildProcess children_;
    private Array!ExitStatus statuses_;
    private PipelineSuccess success_;

    @disable this(this);
    @disable ref Pipeline opAssign(Pipeline source) return;

    bool empty() const pure @safe
    {
        return children_.length == 0;
    }

    size_t length() const pure @safe
    {
        return children_.length;
    }

    bool completed() const @system
    {
        foreach (index; 0 .. children_.length)
        {
            if (children_[index].ownsProcess)
                return false;
        }
        return !empty;
    }

    ProcessId stageId(size_t index) const @system
    {
        version (XTB_Checked)
            require(index < length, "pipeline child index out of bounds");
        return children_[index].id;
    }

    bool stageRunning(size_t index) const @system
    {
        version (XTB_Checked)
            require(index < length, "pipeline child index out of bounds");
        return children_[index].ownsProcess;
    }

    PipeWriter* stdinPipe() return @system
    {
        return empty ? null : children_[0].stdinPipe;
    }

    PipeReader* stdoutPipe() return @system
    {
        return empty ? null : children_[length - 1].stdoutPipe;
    }

    PipeReader* stderrPipe(size_t index) return @system
    {
        version (XTB_Checked)
            require(index < length, "pipeline stderr index out of bounds");
        return children_[index].stderrPipe;
    }

    ExitStatus status(size_t index) const @system
    {
        version (XTB_Checked)
        {
            require(index < length, "pipeline status index out of bounds");
            require(statuses_[index].available,
                "pipeline stage has not exited");
        }
        return statuses_[index];
    }

    bool succeeded() const @system
    {
        version (XTB_Checked)
            require(completed, "live pipeline has no success state");
        if (success_ == PipelineSuccess.lastStage)
        {
            version (XTB_Checked)
                require(statuses_[length - 1].available,
                    "pipeline stage status was consumed externally");
            return statuses_[length - 1].succeeded;
        }
        foreach (status; statuses_.slice)
        {
            version (XTB_Checked)
                require(status.available,
                    "pipeline stage status was consumed externally");
            if (!status.succeeded)
                return false;
        }
        return true;
    }

    /// Releases local stage resources after every child lifecycle is resolved.
    /// Live stages must be explicitly waited or terminated-and-waited before
    /// generic deinitialization.
    void deinit() @system
    {
        version (XTB_Checked)
        {
            foreach (ref child; children_.slice)
                require(!child.ownsProcess,
                    "live Pipeline stage must be resolved before deinit");
        }
        // Array is intentionally shallow, so finalize each child's remaining
        // pipe resources before releasing the backing allocation.
        foreach_reverse (ref child; children_.slice)
            child.deinit();
        children_.clear();
        children_.deinit();
        statuses_.clear();
        statuses_.deinit();
        success_ = PipelineSuccess.init;
    }
}

ProcessError spawnPipeline(
    scope const(PipelineStage)[] stages,
    scope const(PipelineOptions) options,
    Allocator* allocator,
    Pipeline* output,
) @system
{
    return spawnPipelineSlice(stages, options, allocator, output);
}

ProcessError spawnPipeline(
    scope const(Command)[] commands,
    scope const(PipelineOptions) options,
    Allocator* allocator,
    Pipeline* output,
) @system
{
    return spawnPipelineSlice(commands, options, allocator, output);
}

PipelineWaitResult tryWaitPipeline(Pipeline* pipeline) @system
{
    version (XTB_Checked)
        require(pipeline !is null && !pipeline.empty,
            "invalid Pipeline for tryWait");
    size_t running;
    foreach (index; 0 .. pipeline.length)
    {
        ChildProcess* child = &pipeline.children_[index];
        if (!child.ownsProcess)
            continue;
        const result = childTryWait(child);
        if (result.error.failed)
            return PipelineWaitResult(
                stageError(result.error, index, ProcessOperation.pipelineWait),
                PipelineWaitState.running,
                0,
            );
        if (result.state == WaitState.exited)
            pipeline.statuses_[index] = result.status;
        else
            ++running;
    }
    return PipelineWaitResult(
        ProcessError.init,
        running == 0 ? PipelineWaitState.completed
            : PipelineWaitState.running,
        running,
    );
}

ProcessError waitPipeline(Pipeline* pipeline) @system
{
    version (XTB_Checked)
        require(pipeline !is null && !pipeline.empty,
            "invalid Pipeline for wait");
    foreach (index; 0 .. pipeline.length)
    {
        ChildProcess* child = &pipeline.children_[index];
        if (!child.ownsProcess)
            continue;
        ExitStatus status;
        const error = childWait(child, &status);
        if (error.failed)
            return stageError(error, index, ProcessOperation.pipelineWait);
        pipeline.statuses_[index] = status;
    }
    return ProcessError.init;
}

ProcessError requestPipelineTermination(scope Pipeline* pipeline) @system
{
    return signalStages(pipeline, false);
}

ProcessError killPipeline(scope Pipeline* pipeline) @system
{
    return signalStages(pipeline, true);
}

ProcessError terminatePipelineAndWait(Pipeline* pipeline) @system
{
    const signalError = requestPipelineTermination(pipeline);
    if (signalError.failed && signalError.os.kind != OsErrorKind.notFound)
        return signalError;
    return waitPipeline(pipeline);
}

ProcessError killPipelineAndWait(Pipeline* pipeline) @system
{
    const signalError = killPipeline(pipeline);
    if (signalError.failed && signalError.os.kind != OsErrorKind.notFound)
        return signalError;
    return waitPipeline(pipeline);
}

private ProcessError spawnPipelineSlice(Stage)(
    scope const(Stage)[] stages,
    scope const(PipelineOptions) options,
    Allocator* allocator,
    Pipeline* output,
) @system if (is(Stage == Command) || is(Stage == PipelineStage))
{
    version (XTB_Checked)
    {
        require(allocator !is null && *allocator !is null,
            "Pipeline requires a valid allocator");
        require(output !is null, "Pipeline output pointer is null");
        require(output.empty, "Pipeline output must be empty");
    }

    ProcessError error = validatePipeline(stages, options);
    if (error.failed)
        return error;

    Pipeline created;
    scope (exit)
        rollbackPipelineSpawn(&created);
    Array!ChildProcess children = Array!ChildProcess.create(allocator);
    Array!ExitStatus statuses = Array!ExitStatus.create(allocator);
    moveEmplace(children, created.children_);
    moveEmplace(statuses, created.statuses_);
    created.success_ = options.success;
    if (!created.children_.tryResize(stages.length) ||
        !created.statuses_.tryResize(stages.length))
        return ProcessError(
            OsError(OsErrorKind.resourceExhausted, 0),
            ProcessOperation.pipelineSpawn,
        );

    PipeReader pendingInput;
    scope (exit)
        pendingInput.deinit();
    foreach (index; 0 .. stages.length)
    {
        Pipe connection;
        scope (exit)
            connection.deinit();
        if (index + 1 != stages.length)
        {
            const pipeError = createPipe(PipeOptions.init, &connection);
            if (pipeError.failed)
                return ProcessError(
                    pipeError,
                    ProcessOperation.pipelineSpawn,
                    index,
                );
        }

        SpawnOptions spawnOptions;
        spawnOptions.stdin = index == 0
            ? cast(InputRoute) options.stdin : InputRoute.borrow(&pendingInput);
        spawnOptions.stdout = index + 1 == stages.length
            ? cast(OutputRoute) options.stdout
            : OutputRoute.borrow(&connection.writer);
        spawnOptions.stderr = stageStderr(
            stages[index], cast(ErrorRoute) options.stderr,
        );
        spawnOptions.isolation = options.isolation;
        spawnOptions.signalMask = options.signalMask;
        error = spawn(
            stageCommand(stages[index]),
            spawnOptions,
            &created.children_[index],
        );
        if (error.failed)
            return stageError(error, index, ProcessOperation.pipelineSpawn);

        if (pendingInput.valid)
        {
            const closeError = close(&pendingInput);
            if (closeError.failed)
                return ProcessError(
                    closeError,
                    ProcessOperation.pipelineSpawn,
                    index,
                );
        }
        if (connection.writer.valid)
        {
            const closeError = close(&connection.writer);
            if (closeError.failed)
                return ProcessError(
                    closeError,
                    ProcessOperation.pipelineSpawn,
                    index,
                );
        }
        if (connection.reader.valid)
            moveAssign(connection.reader, pendingInput);
    }

    moveAssign(created, *output);
    return ProcessError.init;
}

private void rollbackPipelineSpawn(Pipeline* pipeline) @system
{
    foreach_reverse (ref child; pipeline.children_.slice)
        rollbackSpawnedProcess(&child);
    pipeline.deinit();
}

private ProcessError validatePipeline(Stage)(
    scope const(Stage)[] stages,
    scope const(PipelineOptions) options,
) @system if (is(Stage == Command) || is(Stage == PipelineStage))
{
    if (stages.length == 0 ||
        cast(u8) options.success > cast(u8) PipelineSuccess.everyStage ||
        cast(u8) options.isolation > cast(u8) ProcessIsolation.isolatedTree ||
        cast(u8) options.signalMask > cast(u8) SignalMaskPolicy.inherit)
        return ProcessError(
            OsError(OsErrorKind.invalidArgument, 0),
            ProcessOperation.pipelineSpawn,
        );

    foreach (index; 0 .. stages.length)
    {
        ProcessError error = validate(stageCommand(stages[index]));
        if (error.failed)
            return stageError(error, index, ProcessOperation.pipelineSpawn);
        SpawnOptions spawnOptions;
        spawnOptions.stdin = index == 0
            ? cast(InputRoute) options.stdin : InputRoute.piped();
        spawnOptions.stdout = index + 1 == stages.length
            ? cast(OutputRoute) options.stdout : OutputRoute.piped();
        spawnOptions.stderr = stageStderr(
            stages[index], cast(ErrorRoute) options.stderr,
        );
        spawnOptions.isolation = options.isolation;
        spawnOptions.signalMask = options.signalMask;
        error = validate(spawnOptions);
        if (error.failed)
            return stageError(error, index, ProcessOperation.pipelineSpawn);
    }
    return ProcessError.init;
}

private ref const(Command) stageCommand(Stage)(ref const(Stage) stage) @system
{
    static if (is(Stage == Command))
        return stage;
    else
        return stage.command;
}

private ErrorRoute stageStderr(Stage)(
    ref const(Stage) stage,
    ErrorRoute defaultRoute,
) @system
{
    static if (is(Stage == PipelineStage))
    {
        if (stage.stderrOverride.isSome)
            return cast(ErrorRoute) stage.stderrOverride.value;
    }
    return defaultRoute;
}

private ProcessError signalStages(Pipeline* pipeline, bool forceful) @system
{
    version (XTB_Checked)
        require(pipeline !is null && !pipeline.empty,
            "invalid Pipeline for termination");
    ProcessError firstError;
    foreach (index; 0 .. pipeline.length)
    {
        ChildProcess* child = &pipeline.children_[index];
        if (!child.ownsProcess)
            continue;
        ProcessError error = forceful
            ? childKill(child) : childRequestTermination(child);
        if (error.failed && error.os.kind != OsErrorKind.notFound &&
            firstError.succeeded)
            firstError = stageError(
                error,
                index,
                forceful ? ProcessOperation.kill
                    : ProcessOperation.requestTermination,
            );
    }
    return firstError;
}

private ProcessError stageError(
    ProcessError error,
    size_t index,
    ProcessOperation operation,
) pure @safe
{
    error.operation = operation;
    error.stageIndex = index;
    return error;
}

unittest
{
    String[1] firstArguments = ["first"];
    String[1] secondArguments = ["second"];
    Command[2] commands = [
        Command.search("one", firstArguments[]),
        Command.search("two", secondArguments[]),
    ];
    PipelineStage[2] stages = [
        PipelineStage(commands[0]),
        PipelineStage(commands[1]).withStderr(ErrorRoute.nullDevice()),
    ];
    assert(stages[1].stderrOverride.isSome);
    const options = PipelineOptions.init
        .withStdin(InputRoute.piped())
        .withStdout(OutputRoute.piped())
        .withStderr(ErrorRoute.piped())
        .withSuccessPolicy(PipelineSuccess.everyStage)
        .withIsolation(ProcessIsolation.isolatedTree);
    assert(options.success == PipelineSuccess.everyStage);
}
