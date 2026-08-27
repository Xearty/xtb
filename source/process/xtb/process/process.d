module xtb.process.process;

nothrow @nogc:

import xtb.lifetime : moveAssign;
import core.stdc.string : memmove;
import xtb.memory : Allocator, allocateArray, allocateZeroedArray;
import xtb.option : Option, some;

version (XTB_Checked) import xtb.panic : require;
import xtb.string;
import xtb.thread_context : ScratchScope;
import xtb.types : u32, u64, u8;
import xtb.os.error : OsError, OsErrorKind;
import xtb.fs.file : File;
import xtb.fs.path : Path;
import xtb.os.pipe : Pipe, PipeMode, PipeOptions, PipeReader, PipeWriter,
    close, createPipe;
import xtb.os.time : monotonicNanoseconds, sleepNanoseconds;
import xtb.time : Timeout, TimeoutKind;
import xtb.process.internal.process_backend : NativeProcessWatchState,
    NativeRoute, NativeRouteKind, NativeSignal, NativeSpawnOptions,
    NativeWaitState;

version (linux)
    private import backend = xtb.process.internal.linux.process;
else
    private import backend = xtb.process.internal.unsupported.process;

private alias NativeSpawn = backend.NativeSpawn;

enum ProcessOperation : ubyte
{
    none,
    validate,
    createPipe,
    spawn,
    wait,
    requestTermination,
    kill,
    communicate,
    pipelineSpawn,
    pipelineWait,
}

enum noStageIndex = size_t.max;

struct ProcessError
{
nothrow @nogc:

    OsError os;
    ProcessOperation operation;
    size_t stageIndex = noStageIndex;

    bool failed() const pure @safe
    {
        return os.failed;
    }

    bool succeeded() const pure @safe
    {
        return os.succeeded;
    }
}

enum ExecutableLookup : ubyte
{
    exact,
    searchPath,
}

enum EnvironmentMode : ubyte
{
    inherit,
    replace,
    overlay,
}

enum EnvironmentAction : ubyte
{
    set,
    remove,
}

struct EnvironmentEntry
{
    String name;
    String value;
    EnvironmentAction action;
}

struct Environment
{
    EnvironmentMode mode;
    const(EnvironmentEntry)[] entries;
}

struct Command
{
nothrow @nogc:

    private String executable_;
    private const(String)[] arguments_;
    private String argumentZero_;
    private Option!Path workingDirectory_;
    private Environment environment_;
    private ExecutableLookup lookup_;

    static Command exact(Path executable, const(String)[] arguments = null)
    {
        Command result;
        result.executable_ = executable.view;
        result.arguments_ = arguments;
        return result;
    }

    static Command search(String executable, const(String)[] arguments = null)
    {
        Command result;
        result.executable_ = executable;
        result.arguments_ = arguments;
        result.lookup_ = ExecutableLookup.searchPath;
        return result;
    }

    String executable() const return scope pure @safe
    {
        return executable_;
    }

    const(String)[] arguments() const return scope pure @safe
    {
        return arguments_;
    }

    ExecutableLookup lookup() const pure @safe
    {
        return lookup_;
    }
}

void setArguments(ref Command command, const(String)[] arguments)
{
    command.arguments_ = arguments;
}

void setWorkingDirectory(ref Command command, Path path)
{
    command.workingDirectory_ = some(path);
}

void clearWorkingDirectory(ref Command command)
{
    command.workingDirectory_.reset();
}

void setArgumentZero(ref Command command, String value)
{
    command.argumentZero_ = value;
}

void setEnvironment(ref Command command, Environment environment)
{
    command.environment_ = environment;
}

private enum RouteKind : u8
{
    inherited,
    nullDevice,
    piped,
    file,
    pipe,
    mergeWithStdout,
}

struct InputRoute
{
nothrow @nogc:

    private RouteKind kind_;
    private void* owner_;

    static InputRoute inherited() pure @safe
    {
        return InputRoute.init;
    }

    static InputRoute nullDevice() pure @safe
    {
        return InputRoute(RouteKind.nullDevice, null);
    }

    static InputRoute piped() pure @safe
    {
        return InputRoute(RouteKind.piped, null);
    }

    static InputRoute borrow(File* file) @system
    {
        version (XTB_Checked)
            require(file !is null, "borrowed input File pointer is null");
        return InputRoute(RouteKind.file, file);
    }

    static InputRoute borrow(PipeReader* reader) @system
    {
        version (XTB_Checked)
            require(reader !is null, "borrowed input PipeReader pointer is null");
        return InputRoute(RouteKind.pipe, reader);
    }
}

struct OutputRoute
{
nothrow @nogc:

    private RouteKind kind_;
    private void* owner_;

    static OutputRoute inherited() pure @safe
    {
        return OutputRoute.init;
    }

    static OutputRoute nullDevice() pure @safe
    {
        return OutputRoute(RouteKind.nullDevice, null);
    }

    static OutputRoute piped() pure @safe
    {
        return OutputRoute(RouteKind.piped, null);
    }

    static OutputRoute borrow(File* file) @system
    {
        version (XTB_Checked)
            require(file !is null, "borrowed output File pointer is null");
        return OutputRoute(RouteKind.file, file);
    }

    static OutputRoute borrow(PipeWriter* writer) @system
    {
        version (XTB_Checked)
            require(writer !is null, "borrowed output PipeWriter pointer is null");
        return OutputRoute(RouteKind.pipe, writer);
    }
}

struct ErrorRoute
{
nothrow @nogc:

    private RouteKind kind_;
    private void* owner_;

    static ErrorRoute inherited() pure @safe
    {
        return ErrorRoute.init;
    }

    static ErrorRoute nullDevice() pure @safe
    {
        return ErrorRoute(RouteKind.nullDevice, null);
    }

    static ErrorRoute piped() pure @safe
    {
        return ErrorRoute(RouteKind.piped, null);
    }

    static ErrorRoute borrow(File* file) @system
    {
        version (XTB_Checked)
            require(file !is null, "borrowed error File pointer is null");
        return ErrorRoute(RouteKind.file, file);
    }

    static ErrorRoute borrow(PipeWriter* writer) @system
    {
        version (XTB_Checked)
            require(writer !is null, "borrowed error PipeWriter pointer is null");
        return ErrorRoute(RouteKind.pipe, writer);
    }

    static ErrorRoute mergeWithStdout() pure @safe
    {
        return ErrorRoute(RouteKind.mergeWithStdout, null);
    }
}

enum ProcessIsolation : u8
{
    direct,
    isolatedTree,
}

enum SignalMaskPolicy : u8
{
    clear,
    inherit,
}

struct SpawnOptions
{
    InputRoute stdin;
    OutputRoute stdout;
    ErrorRoute stderr;
    ProcessIsolation isolation;
    SignalMaskPolicy signalMask;
}

SpawnOptions withStdin(SpawnOptions options, InputRoute route) pure @safe
{
    options.stdin = route;
    return options;
}

SpawnOptions withStdout(SpawnOptions options, OutputRoute route) pure @safe
{
    options.stdout = route;
    return options;
}

SpawnOptions withStderr(SpawnOptions options, ErrorRoute route) pure @safe
{
    options.stderr = route;
    return options;
}

SpawnOptions withIsolation(
    SpawnOptions options,
    ProcessIsolation isolation,
) pure @safe
{
    options.isolation = isolation;
    return options;
}

SpawnOptions withSignalMask(
    SpawnOptions options,
    SignalMaskPolicy policy,
) pure @safe
{
    options.signalMask = policy;
    return options;
}

struct ProcessId
{
nothrow @nogc:

    private u64 value_;

    u64 value() const pure @safe
    {
        return value_;
    }
}

enum ExitKind : u8
{
    none,
    exited,
    signaled,
}

struct ExitStatus
{
nothrow @nogc:

    private ExitKind kind_;
    private u32 code_;
    private bool coreDumped_;

    ExitKind kind() const pure @safe
    {
        return kind_;
    }

    bool succeeded() const pure @safe
    {
        return kind_ == ExitKind.exited && code_ == 0;
    }

    bool exited() const pure @safe
    {
        return kind_ == ExitKind.exited;
    }

    bool signaled() const pure @safe
    {
        return kind_ == ExitKind.signaled;
    }

    bool available() const pure @safe
    {
        return kind_ != ExitKind.none;
    }

    u32 exitCode() const @safe
    {
        version (XTB_Checked)
            require(exited, "signaled process has no exit code");
        return code_;
    }

    u32 terminationSignal() const @safe
    {
        version (XTB_Checked)
            require(signaled, "exited process has no termination signal");
        return code_;
    }

    bool coreDumped() const @safe
    {
        version (XTB_Checked)
            require(signaled, "exited process has no core-dump state");
        return coreDumped_;
    }
}

enum WaitState : u8
{
    running,
    exited,
}

struct WaitResult
{
    ProcessError error;
    WaitState state;
    ExitStatus status;
}

/// Owning handle for a spawned child and any parent-side standard-I/O pipes.
///
/// Process lifecycle is explicit: a live child must be reaped with `wait`,
/// `terminateAndWait`, `killAndWait`, or an equivalent operation before
/// `deinit`. Generic deinitialization only releases remaining local pipe state;
/// it never chooses to terminate or wait for a live child.
struct ChildProcess
{
nothrow @nogc:

    private int processId_ = -1;
    private ProcessIsolation isolation_;
    private PipeWriter stdinPipe_;
    private PipeReader stdoutPipe_;
    private PipeReader stderrPipe_;

    @disable this(this);
    @disable ref ChildProcess opAssign(ChildProcess source) return;

    bool ownsProcess() const pure @safe
    {
        return processId_ > 0;
    }

    bool empty() const pure @safe
    {
        return !ownsProcess && !stdinPipe_.valid && !stdoutPipe_.valid &&
            !stderrPipe_.valid;
    }

    ProcessId id() const @safe
    {
        version (XTB_Checked)
            require(ownsProcess, "empty ChildProcess has no id");
        return ProcessId(cast(u64) processId_);
    }

    bool hasStdinPipe() const pure @safe
    {
        return stdinPipe_.valid;
    }

    bool hasStdoutPipe() const pure @safe
    {
        return stdoutPipe_.valid;
    }

    bool hasStderrPipe() const pure @safe
    {
        return stderrPipe_.valid;
    }

    PipeWriter* stdinPipe() return @system
    {
        return stdinPipe_.valid ? &stdinPipe_ : null;
    }

    PipeReader* stdoutPipe() return @system
    {
        return stdoutPipe_.valid ? &stdoutPipe_ : null;
    }

    PipeReader* stderrPipe() return @system
    {
        return stderrPipe_.valid ? &stderrPipe_ : null;
    }

    /// Releases local pipe resources after the child lifecycle is resolved.
    /// A live child must be explicitly waited, terminated-and-waited, or
    /// killed-and-waited before generic deinitialization.
    void deinit() @system
    {
        version (XTB_Checked)
            require(!ownsProcess,
                "live ChildProcess must be resolved before deinit");
        stdinPipe_.deinit();
        stdoutPipe_.deinit();
        stderrPipe_.deinit();
        isolation_ = ProcessIsolation.init;
    }
}

ProcessError validate(scope const(Command) command) @system
{
    return validateCommand(command);
}

ProcessError validate(scope const(SpawnOptions) options) @system
{
    return validateOptions(options);
}

ProcessError spawn(
    scope const(Command) command,
    scope const(SpawnOptions) options,
    ChildProcess* output,
) @system
{
    version (XTB_Checked)
    {
        require(output !is null, "ChildProcess output pointer is null");
        require(output.empty, "ChildProcess output must be empty");
    }

    ProcessError error = validateCommand(command);
    if (error.failed)
        return error;
    error = validateOptions(options);
    if (error.failed)
        return error;

    Pipe childInput;
    Pipe childOutput;
    Pipe childError;
    scope (exit)
    {
        childInput.deinit();
        childOutput.deinit();
        childError.deinit();
    }
    int stdinDescriptor = routeDescriptor(options.stdin);
    int stdoutDescriptor = routeDescriptor(options.stdout);
    int stderrDescriptor = routeDescriptor(options.stderr);

    if (options.stdin.kind_ == RouteKind.piped)
    {
        PipeOptions pipeOptions;
        pipeOptions.writerMode = PipeMode.nonBlocking;
        const pipeError = createPipe(pipeOptions, &childInput);
        if (pipeError.failed)
            return ProcessError(pipeError, ProcessOperation.createPipe);
        stdinDescriptor = childInput.reader.nativeDescriptor;
    }
    if (options.stdout.kind_ == RouteKind.piped)
    {
        PipeOptions pipeOptions;
        pipeOptions.readerMode = PipeMode.nonBlocking;
        const pipeError = createPipe(pipeOptions, &childOutput);
        if (pipeError.failed)
            return ProcessError(pipeError, ProcessOperation.createPipe);
        stdoutDescriptor = childOutput.writer.nativeDescriptor;
    }
    if (options.stderr.kind_ == RouteKind.piped)
    {
        PipeOptions pipeOptions;
        pipeOptions.readerMode = PipeMode.nonBlocking;
        const pipeError = createPipe(pipeOptions, &childError);
        if (pipeError.failed)
            return ProcessError(pipeError, ProcessOperation.createPipe);
        stderrDescriptor = childError.writer.nativeDescriptor;
    }

    int processId;
    error = spawnPlatform(
        command,
        options,
        stdinDescriptor,
        stdoutDescriptor,
        stderrDescriptor,
        &processId,
    );
    if (error.failed)
        return error;

    close(&childInput.reader);
    close(&childOutput.writer);
    close(&childError.writer);
    output.processId_ = processId;
    output.isolation_ = options.isolation;
    if (options.stdin.kind_ == RouteKind.piped)
        moveAssign(childInput.writer, output.stdinPipe_);
    if (options.stdout.kind_ == RouteKind.piped)
        moveAssign(childOutput.reader, output.stdoutPipe_);
    if (options.stderr.kind_ == RouteKind.piped)
        moveAssign(childError.reader, output.stderrPipe_);
    return ProcessError.init;
}

WaitResult tryWait(ChildProcess* child) @system
{
    version (XTB_Checked)
        require(child !is null && child.ownsProcess,
            "invalid ChildProcess for tryWait");
    return waitPlatform(child, true);
}

WaitResult waitFor(ChildProcess* child, Timeout timeout) @system
{
    version (XTB_Checked)
        require(child !is null && child.ownsProcess,
            "invalid ChildProcess for waitFor");
    if (cast(u8) timeout.kind > cast(u8) TimeoutKind.finite)
        return WaitResult(
            invalidProcessError(ProcessOperation.wait),
            WaitState.running,
            ExitStatus.init,
        );
    if (timeout.isImmediate)
        return tryWait(child);
    if (timeout.isInfinite)
        return waitPlatform(child, false);
    return waitForPlatform(child, timeout);
}

ProcessError wait(ChildProcess* child, ExitStatus* output) @system
{
    version (XTB_Checked)
    {
        require(child !is null && child.ownsProcess,
            "invalid ChildProcess for wait");
        require(output !is null, "ExitStatus output pointer is null");
    }
    *output = ExitStatus.init;
    const result = waitPlatform(child, false);
    if (result.error.succeeded)
        *output = result.status;
    return result.error;
}

ProcessError requestTermination(scope const(ChildProcess)* child) @system
{
    version (XTB_Checked)
        require(child !is null && child.ownsProcess,
            "invalid ChildProcess for termination");
    return signalPlatform(
        child,
        NativeSignal.terminate,
        ProcessOperation.requestTermination,
    );
}

ProcessError kill(scope const(ChildProcess)* child) @system
{
    version (XTB_Checked)
        require(child !is null && child.ownsProcess,
            "invalid ChildProcess for kill");
    return signalPlatform(child, NativeSignal.kill, ProcessOperation.kill);
}

ProcessError terminateAndWait(ChildProcess* child, ExitStatus* output) @system
{
    const signalError = requestTermination(child);
    if (signalError.failed && signalError.os.kind != OsErrorKind.notFound)
        return signalError;
    const waitError = wait(child, output);
    return waitError;
}

ProcessError killAndWait(ChildProcess* child, ExitStatus* output) @system
{
    const signalError = kill(child);
    if (signalError.failed && signalError.os.kind != OsErrorKind.notFound)
        return signalError;
    const waitError = wait(child, output);
    return waitError;
}

private ProcessError validateCommand(scope const(Command) command) @system
{
    if (cast(u8) command.lookup_ > cast(u8) ExecutableLookup.searchPath ||
        command.executable_.length == 0 || command.executable_.containsNul ||
        command.executable_.length == size_t.max ||
        command.argumentZero_.containsNul ||
        command.argumentZero_.length == size_t.max ||
        cast(u8) command.environment_.mode > cast(u8) EnvironmentMode.overlay)
        return invalidProcessError(ProcessOperation.validate);
    if (command.environment_.mode == EnvironmentMode.inherit &&
        command.environment_.entries.length != 0)
        return invalidProcessError(ProcessOperation.validate);
    foreach (argument; command.arguments_)
    {
        if (argument.containsNul || argument.length == size_t.max)
            return invalidProcessError(ProcessOperation.validate);
    }
    if (command.workingDirectory_.isSome &&
        (command.workingDirectory_.value.view.containsNul ||
            command.workingDirectory_.value.view.length == size_t.max))
        return invalidProcessError(ProcessOperation.validate);
    foreach (i, entry; command.environment_.entries)
    {
        if (entry.name.length == 0 || entry.name.containsNul ||
            entry.name.containsCodeUnit('=') || entry.value.containsNul ||
            cast(u8) entry.action > cast(
                u8) EnvironmentAction.remove ||
            (entry.action == EnvironmentAction.remove && entry.value.length != 0) ||
            entry.value.length > size_t.max - 2 ||
            entry.name.length > size_t.max - entry.value.length - 2)
            return invalidProcessError(ProcessOperation.validate);
        foreach (previous; command.environment_.entries[0 .. i])
        {
            if (entry.name.equal(previous.name))
                return invalidProcessError(ProcessOperation.validate);
        }
    }
    return ProcessError.init;
}

private ProcessError validateOptions(scope const(SpawnOptions) options) @system
{
    if (cast(u8) options.isolation > cast(u8) ProcessIsolation.isolatedTree ||
        cast(u8) options.signalMask > cast(u8) SignalMaskPolicy.inherit ||
        !validInputRoute(
            options.stdin) ||
        !validOutputRoute(options.stdout) ||
        !validErrorRoute(options.stderr))
        return invalidProcessError(ProcessOperation.validate);
    return ProcessError.init;
}

private bool validInputRoute(scope const(InputRoute) route) @system
{
    switch (route.kind_)
    {
        case RouteKind.inherited:
        case RouteKind.nullDevice:
        case RouteKind.piped:
            return route.owner_ is null;
        case RouteKind.file:
            return route.owner_ !is null && (cast(File*) route.owner_).valid;
        case RouteKind.pipe:
            return route.owner_ !is null &&
                (cast(PipeReader*) route.owner_).valid;
        default:
            return false;
    }
}

private bool validOutputRoute(scope const(OutputRoute) route) @system
{
    switch (route.kind_)
    {
        case RouteKind.inherited:
        case RouteKind.nullDevice:
        case RouteKind.piped:
            return route.owner_ is null;
        case RouteKind.file:
            return route.owner_ !is null && (cast(File*) route.owner_).valid;
        case RouteKind.pipe:
            return route.owner_ !is null &&
                (cast(PipeWriter*) route.owner_).valid;
        default:
            return false;
    }
}

private bool validErrorRoute(scope const(ErrorRoute) route) @system
{
    if (route.kind_ == RouteKind.mergeWithStdout)
        return route.owner_ is null;
    return validOutputRoute(OutputRoute(route.kind_, cast(void*) route.owner_));
}

private int routeDescriptor(scope const(InputRoute) route) @system
{
    if (route.kind_ == RouteKind.file)
        return (cast(File*) route.owner_).nativeDescriptor;
    if (route.kind_ == RouteKind.pipe)
        return (cast(PipeReader*) route.owner_).nativeDescriptor;
    return -1;
}

private int routeDescriptor(scope const(OutputRoute) route) @system
{
    if (route.kind_ == RouteKind.file)
        return (cast(File*) route.owner_).nativeDescriptor;
    if (route.kind_ == RouteKind.pipe)
        return (cast(PipeWriter*) route.owner_).nativeDescriptor;
    return -1;
}

private int routeDescriptor(scope const(ErrorRoute) route) @system
{
    return routeDescriptor(OutputRoute(route.kind_, cast(void*) route.owner_));
}

private ProcessError invalidProcessError(ProcessOperation operation) pure @safe
{
    return ProcessError(OsError(OsErrorKind.invalidArgument, 0), operation);
}

private ProcessError spawnPlatform(
    scope const(Command) command,
    scope const(SpawnOptions) options,
    int stdinDescriptor,
    int stdoutDescriptor,
    int stderrDescriptor,
    int* output,
) @system
{
    version (XTB_Checked)
        require(output !is null, "native process id output pointer is null");
    *output = -1;
    const policyError = backend.validateChildReapingPolicy();
    if (policyError.failed)
        return ProcessError(policyError, ProcessOperation.spawn);

    ScratchScope scratch = ScratchScope.acquire();
    const executable = copyCString(command.executable_, scratch.allocator);
    const argumentZero = command.argumentZero_.length == 0
        ? executable
        : copyCString(command.argumentZero_, scratch.allocator);
    if (command.arguments_.length > size_t.max - 2)
        return invalidProcessError(ProcessOperation.validate);
    const argvCount = command.arguments_.length + 2;
    const(char)** argv = scratch.allocator.allocateArray!(const(char)*)(argvCount).ptr;
    argv[0] = argumentZero;
    foreach (i, argument; command.arguments_)
        argv[i + 1] = copyCString(argument, scratch.allocator);
    argv[argvCount - 1] = null;

    const(char)** environment;
    const environmentError = buildEnvironment(
        command.environment_,
        scratch.allocator,
        backend.currentEnvironment(),
        &environment,
    );
    if (environmentError.failed)
        return ProcessError(environmentError, ProcessOperation.validate);

    const(char)* workingDirectory;
    if (command.workingDirectory_.isSome)
        workingDirectory = copyCString(
            command.workingDirectory_.value.view,
            scratch.allocator,
        );

    NativeSpawnOptions nativeOptions;
    nativeOptions.stdin = toNativeRoute(options.stdin.kind_, stdinDescriptor);
    nativeOptions.stdout = toNativeRoute(options.stdout.kind_, stdoutDescriptor);
    nativeOptions.stderr = toNativeRoute(options.stderr.kind_, stderrDescriptor);
    nativeOptions.isolatedTree = options.isolation == ProcessIsolation.isolatedTree;
    nativeOptions.clearSignalMask = options.signalMask == SignalMaskPolicy.clear;
    nativeOptions.workingDirectory = workingDirectory;

    NativeSpawn spawnState;
    scope (exit)
        spawnState.deinit();
    OsError error = spawnState.prepare(nativeOptions);
    if (error.failed)
        return ProcessError(error, ProcessOperation.spawn);

    int processId;
    if (command.lookup_ == ExecutableLookup.searchPath &&
        !command.executable_.containsCodeUnit('/'))
        error = spawnSearchPath(
            &spawnState,
            command.executable_,
            argv,
            environment,
            scratch.allocator,
            &processId,
        );
    else
        error = spawnState.execute(executable, argv, environment, &processId);
    if (error.failed)
        return ProcessError(error, ProcessOperation.spawn);
    *output = processId;
    return ProcessError.init;
}

private NativeRoute toNativeRoute(RouteKind kind, int descriptor) pure @safe
{
    switch (kind)
    {
        case RouteKind.inherited:
            return NativeRoute(NativeRouteKind.inherited, -1);
        case RouteKind.nullDevice:
            return NativeRoute(NativeRouteKind.nullDevice, -1);
        case RouteKind.piped:
        case RouteKind.file:
        case RouteKind.pipe:
            return NativeRoute(NativeRouteKind.descriptor, descriptor);
        case RouteKind.mergeWithStdout:
            return NativeRoute(NativeRouteKind.mergeWithStdout, -1);
        default:
            return NativeRoute(NativeRouteKind.inherited, -1);
    }
}

private OsError spawnSearchPath(
    NativeSpawn* spawnState,
    String executable,
    const(char)** argv,
    const(char)** environment,
    Allocator* allocator,
    int* output,
) @system
{
    String path;
    const pathError = environmentValue(environment, "PATH", &path);
    if (pathError.failed)
        return pathError;
    if (path.ptr is null)
        path = "/bin:/usr/bin";

    StringBuf candidate = StringBuf.create(allocator);
    OsError accessError;
    size_t begin;
    for (;;)
    {
        size_t end = begin;
        while (end < path.length && path[end] != ':')
            ++end;
        candidate.clear();
        if (end != begin)
        {
            candidate.append(path[begin .. end]);
            if (candidate.view[$ - 1] != '/')
                candidate.append('/');
        }
        candidate.append(executable);
        const error = spawnState.execute(
            candidate.checkedCString,
            argv,
            environment,
            output,
        );
        if (error.succeeded)
            return error;
        if (error.kind == OsErrorKind.permissionDenied)
            accessError = error;
        else if (error.kind != OsErrorKind.notFound &&
            error.kind != OsErrorKind.notDirectory)
            return error;

        if (end == path.length)
            break;
        begin = end + 1;
    }
    return accessError.failed
        ? accessError : OsError(OsErrorKind.notFound, 0);
}

private OsError buildEnvironment(
    scope const(Environment) environment,
    Allocator* allocator,
    const(char)** inherited,
    const(char)*** output,
) @system
{
    version (XTB_Checked)
        require(output !is null, "environment output pointer is null");
    if (environment.mode == EnvironmentMode.inherit)
    {
        *output = inherited;
        return OsError.init;
    }

    size_t inheritedCount;
    if (environment.mode == EnvironmentMode.overlay)
    {
        while (inherited[inheritedCount]!is null)
            ++inheritedCount;
    }
    if (environment.entries.length > size_t.max - inheritedCount - 1)
        return OsError(OsErrorKind.invalidArgument, 0);
    const capacity = inheritedCount + environment.entries.length + 1;
    const(char)** result = allocator.allocateArray!(const(char)*)(capacity).ptr;
    bool* emitted = allocator
        .allocateZeroedArray!bool(environment.entries.length).ptr;

    size_t length;
    foreach (i; 0 .. inheritedCount)
    {
        const checked = fromCString(inherited[i]);
        if (checked.failed)
            return OsError(OsErrorKind.invalidData, 0);
        const name = environmentEntryName(checked.value);
        const index = findEnvironmentEntry(environment.entries, name);
        if (index == size_t.max)
            result[length++] = inherited[i];
        else
        {
            emitted[index] = true;
            const entry = environment.entries[index];
            if (entry.action == EnvironmentAction.set)
                result[length++] = makeEnvironmentEntry(entry, allocator);
        }
    }
    foreach (i, entry; environment.entries)
    {
        if (!emitted[i] && entry.action == EnvironmentAction.set)
            result[length++] = makeEnvironmentEntry(entry, allocator);
    }
    result[length] = null;
    *output = result;
    return OsError.init;
}

private const(char)* makeEnvironmentEntry(
    scope const(EnvironmentEntry) entry,
    Allocator* allocator,
) @system
{
    const length = entry.name.length + 1 + entry.value.length;
    char* result = allocator.allocateArray!char(length + 1).ptr;
    memmove(result, entry.name.ptr, entry.name.length);
    result[entry.name.length] = '=';
    if (entry.value.length != 0)
        memmove(
            result + entry.name.length + 1,
            entry.value.ptr,
            entry.value.length,
        );
    result[length] = '\0';
    return result;
}

private size_t findEnvironmentEntry(
    scope const(EnvironmentEntry)[] entries,
    String name,
) @system
{
    foreach (i, entry; entries)
    {
        if (entry.name.equal(name))
            return i;
    }
    return size_t.max;
}

private String environmentEntryName(String entry) @safe
{
    size_t length;
    while (length < entry.length && entry[length] != '=')
        ++length;
    return entry[0 .. length];
}

private OsError environmentValue(
    const(char)** environment,
    String name,
    String* output,
) @system
{
    version (XTB_Checked)
        require(output !is null, "environment value output is null");
    *output = String.init;
    for (size_t i; environment[i]!is null; ++i)
    {
        const checked = fromCString(environment[i]);
        if (checked.failed)
            return OsError(OsErrorKind.invalidData, 0);
        const entry = checked.value;
        if (entry.length > name.length && entry[name.length] == '=' &&
            entry[0 .. name.length].equal(name))
        {
            *output = entry[name.length + 1 .. $];
            return OsError.init;
        }
    }
    return OsError.init;
}

private const(char)* copyCString(
    String source,
    Allocator* allocator,
) @system
{
    char* result = allocator.allocateArray!char(source.length + 1).ptr;
    if (source.length != 0)
        memmove(result, source.ptr, source.length);
    result[source.length] = '\0';
    return result;
}

private WaitResult waitPlatform(ChildProcess* child, bool nonBlocking) @system
{
    const native = backend.waitProcess(child.processId_, nonBlocking);
    if (native.error.failed)
        return waitError(native.error);
    if (native.state == NativeWaitState.running)
        return WaitResult(ProcessError.init, WaitState.running, ExitStatus.init);

    child.processId_ = -1;
    ExitStatus status;
    final switch (native.state)
    {
        case NativeWaitState.running:
            return WaitResult(ProcessError.init, WaitState.running, ExitStatus.init);
        case NativeWaitState.exited:
            status = ExitStatus(ExitKind.exited, native.code, false);
            break;
        case NativeWaitState.signaled:
            status = ExitStatus(ExitKind.signaled, native.code, native.coreDumped);
            break;
    }
    return WaitResult(ProcessError.init, WaitState.exited, status);
}

private WaitResult waitForPlatform(ChildProcess* child, Timeout timeout) @system
{
    u64 started;
    OsError error = monotonicNanoseconds(&started);
    if (error.failed)
        return waitError(error);
    const duration = timeout.duration.totalNanoseconds;
    const deadline = duration > u64.max - started ? u64.max : started + duration;

    const watch = backend.openProcessWatch(child.processId_);
    if (watch.error.failed)
        return waitError(watch.error);
    if (watch.state == NativeProcessWatchState.opened)
    {
        const result = waitOnProcessWatch(child, watch.descriptor, deadline);
        backend.closeProcessWatch(watch.descriptor);
        return result;
    }
    return waitByObservation(child, deadline);
}

private WaitResult waitOnProcessWatch(
    ChildProcess* child,
    int descriptor,
    u64 deadline,
) @system
{
    for (;;)
    {
        u64 now;
        const clockError = monotonicNanoseconds(&now);
        if (clockError.failed)
            return waitError(clockError);
        if (now >= deadline)
            return tryWait(child);

        const result = backend.waitProcessWatch(descriptor, deadline - now);
        if (result.error.failed)
            return waitError(result.error);
        if (result.ready)
            return waitPlatform(child, false);
    }
}

private WaitResult waitByObservation(ChildProcess* child, u64 deadline) @system
{
    enum u64 maximumPause = 10_000_000;
    for (;;)
    {
        const observed = tryWait(child);
        if (observed.error.failed || observed.state == WaitState.exited)
            return observed;

        u64 now;
        const clockError = monotonicNanoseconds(&now);
        if (clockError.failed)
            return waitError(clockError);
        if (now >= deadline)
            return observed;
        const remaining = deadline - now;
        const sleepError = sleepNanoseconds(
            remaining < maximumPause ? remaining : maximumPause,
        );
        if (sleepError.failed)
            return waitError(sleepError);
    }
}

private WaitResult waitError(OsError error) pure @safe
{
    return WaitResult(
        ProcessError(error, ProcessOperation.wait),
        WaitState.running,
        ExitStatus.init,
    );
}

private ProcessError signalPlatform(
    scope const(ChildProcess)* child,
    NativeSignal signal,
    ProcessOperation operation,
) @system
{
    const error = backend.signalProcess(
        child.processId_,
        child.isolation_ == ProcessIsolation.isolatedTree,
        signal,
    );
    return error.succeeded ? ProcessError.init : ProcessError(error, operation);
}

package(xtb.process) void rollbackSpawnedProcess(ChildProcess* child) @system
{
    if (child is null || !child.ownsProcess)
        return;
    forceSignal(child);
    reapIgnoringErrors(child);
}

private void forceSignal(ChildProcess* child) @system
{
    cast(void) signalPlatform(child, NativeSignal.kill, ProcessOperation.kill);
}

private void reapIgnoringErrors(ChildProcess* child) @system
{
    cast(void) waitPlatform(child, false);
    child.processId_ = -1;
}

unittest
{
    assert(ProcessError.init.stageIndex == noStageIndex);
    EnvironmentEntry[2] entries = [
        EnvironmentEntry("NAME", "value", EnvironmentAction.set),
        EnvironmentEntry("OLD", "", EnvironmentAction.remove),
    ];
    Environment environment = Environment(EnvironmentMode.overlay, entries[]);
    String[2] arguments = ["one", "two"];
    Command command = Command.search("tool", arguments[]);
    command.setArgumentZero("custom-tool");
    command.setWorkingDirectory(Path.fromString("/tmp"));
    command.setEnvironment(environment);
    assert(command.executable == "tool");
    assert(command.arguments.length == 2);
    assert(command.lookup == ExecutableLookup.searchPath);
    assert(validate(command).succeeded);
    command.clearWorkingDirectory();

    Command invalid = Command.search("bad\0name");
    assert(validate(invalid).os.kind == OsErrorKind.invalidArgument);
    EnvironmentEntry[2] duplicates = [
        EnvironmentEntry("A", "1", EnvironmentAction.set),
        EnvironmentEntry("A", "2", EnvironmentAction.set),
    ];
    invalid = Command.search("tool");
    invalid.setEnvironment(Environment(EnvironmentMode.replace, duplicates[]));
    assert(validate(invalid).os.kind == OsErrorKind.invalidArgument);

    const options = SpawnOptions.init
        .withStdin(InputRoute.nullDevice())
        .withStdout(OutputRoute.piped())
        .withStderr(ErrorRoute.mergeWithStdout())
        .withIsolation(ProcessIsolation.isolatedTree)
        .withSignalMask(SignalMaskPolicy.inherit);
    assert(options.isolation == ProcessIsolation.isolatedTree);
}
