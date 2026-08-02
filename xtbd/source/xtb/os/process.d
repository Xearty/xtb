module xtb.os.process;

nothrow @nogc:

import core.lifetime : move;
import core.stdc.string : memmove, memset;
import xtb.core.memory : Allocator, allocate;
import xtb.core.option : Option, reset, set, some;
import xtb.core.panic : require;
import xtb.core.string : String, StringBuf, append, checkedCString, clear,
    contains, containsNul, equal, fromCString;
import xtb.core.thread_context : ScratchScope;
import xtb.core.types : u32, u64, u8;
import xtb.os.error : OsError, OsErrorKind, lastError, unsupported;
import xtb.os.file : File;
import xtb.os.path : Path;
import xtb.os.pipe : Pipe, PipeMode, PipeOptions, PipeReader, PipeWriter,
    close, createPipe;
import xtb.os.time : Timeout, TimeoutKind, monotonicNanoseconds,
    sleepNanoseconds;

version (linux) import xtb.os.error : fromErrno;

enum ProcessOperation : ubyte
{
    none,
    validate,
    createPipe,
    spawn,
    wait,
    requestTermination,
    kill,
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
    command.workingDirectory_.set(path);
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
        require(file !is null, "borrowed input File pointer is null");
        return InputRoute(RouteKind.file, file);
    }

    static InputRoute borrow(PipeReader* reader) @system
    {
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
        require(file !is null, "borrowed output File pointer is null");
        return OutputRoute(RouteKind.file, file);
    }

    static OutputRoute borrow(PipeWriter* writer) @system
    {
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
        require(file !is null, "borrowed error File pointer is null");
        return ErrorRoute(RouteKind.file, file);
    }

    static ErrorRoute borrow(PipeWriter* writer) @system
    {
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

    u32 exitCode() const @safe
    {
        require(exited, "signaled process has no exit code");
        return code_;
    }

    u32 terminationSignal() const @safe
    {
        require(signaled, "exited process has no termination signal");
        return code_;
    }

    bool coreDumped() const @safe
    {
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

struct ChildProcess
{
nothrow @nogc:

    private int processId_ = -1;
    private ProcessIsolation isolation_;
    private PipeWriter stdinPipe_;
    private PipeReader stdoutPipe_;
    private PipeReader stderrPipe_;

    @disable this(this);

    ~this()
    {
        deinit();
    }

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
        require(ownsProcess, "empty ChildProcess has no id");
        return ProcessId(cast(u64) processId_);
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

    void deinit() @system
    {
        stdinPipe_.deinit();
        stdoutPipe_.deinit();
        stderrPipe_.deinit();
        if (!ownsProcess)
            return;
        forceSignal(&this);
        reapIgnoringErrors(&this);
    }
}

ProcessError validate(scope const(Command) command) @system
{
    return validateCommand(command);
}

ProcessError spawn(
    scope const(Command) command,
    scope const(SpawnOptions) options,
    ChildProcess* output,
) @system
{
    require(output !is null, "ChildProcess output pointer is null");
    require(output.empty, "ChildProcess output must be empty");

    ProcessError error = validateCommand(command);
    if (error.failed)
        return error;
    error = validateOptions(options);
    if (error.failed)
        return error;

    Pipe childInput;
    Pipe childOutput;
    Pipe childError;
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
    version (linux)
        error = spawnLinux(
            command,
            options,
            stdinDescriptor,
            stdoutDescriptor,
            stderrDescriptor,
            &processId,
        );
    else
        error = ProcessError(unsupported(), ProcessOperation.spawn);
    if (error.failed)
        return error;

    close(&childInput.reader);
    close(&childOutput.writer);
    close(&childError.writer);
    output.processId_ = processId;
    output.isolation_ = options.isolation;
    if (options.stdin.kind_ == RouteKind.piped)
        move(childInput.writer, output.stdinPipe_);
    if (options.stdout.kind_ == RouteKind.piped)
        move(childOutput.reader, output.stdoutPipe_);
    if (options.stderr.kind_ == RouteKind.piped)
        move(childError.reader, output.stderrPipe_);
    return ProcessError.init;
}

WaitResult tryWait(ChildProcess* child) @system
{
    require(child !is null && child.ownsProcess,
        "invalid ChildProcess for tryWait");
    version (linux)
        return waitLinux(child, true);
    else
        return WaitResult(
            ProcessError(unsupported(), ProcessOperation.wait),
            WaitState.running,
            ExitStatus.init,
        );
}

WaitResult waitFor(ChildProcess* child, Timeout timeout) @system
{
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
    version (linux)
    {
        if (timeout.isInfinite)
            return waitLinux(child, false);
        return waitForLinux(child, timeout);
    }
    else
        return WaitResult(
            ProcessError(unsupported(), ProcessOperation.wait),
            WaitState.running,
            ExitStatus.init,
        );
}

ProcessError wait(ChildProcess* child, ExitStatus* output) @system
{
    require(child !is null && child.ownsProcess,
        "invalid ChildProcess for wait");
    require(output !is null, "ExitStatus output pointer is null");
    *output = ExitStatus.init;
    version (linux)
    {
        const result = waitLinux(child, false);
        if (result.error.succeeded)
            *output = result.status;
        return result.error;
    }
    else
        return ProcessError(unsupported(), ProcessOperation.wait);
}

ProcessError requestTermination(scope const(ChildProcess)* child) @system
{
    require(child !is null && child.ownsProcess,
        "invalid ChildProcess for termination");
    version (linux)
    {
        import core.stdc.signal : SIGTERM;

        return signalLinux(child, SIGTERM, ProcessOperation.requestTermination);
    }
    else
        return ProcessError(unsupported(), ProcessOperation.requestTermination);
}

ProcessError kill(scope const(ChildProcess)* child) @system
{
    require(child !is null && child.ownsProcess,
        "invalid ChildProcess for kill");
    version (linux)
    {
        import core.sys.posix.signal : SIGKILL;

        return signalLinux(child, SIGKILL, ProcessOperation.kill);
    }
    else
        return ProcessError(unsupported(), ProcessOperation.kill);
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
            entry.name.contains('=') || entry.value.containsNul ||
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

version (linux) private ProcessError spawnLinux(
    scope const(Command) command,
    scope const(SpawnOptions) options,
    int stdinDescriptor,
    int stdoutDescriptor,
    int stderrDescriptor,
    int* output,
) @system
{
    import core.sys.posix.unistd : environ;

    require(output !is null, "native process id output pointer is null");
    *output = -1;
    const policyError = validateSigchldPolicy();
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
    const(char)** argv = scratch.allocator.allocate!(const(char)*)(argvCount);
    argv[0] = argumentZero;
    foreach (i, argument; command.arguments_)
        argv[i + 1] = copyCString(argument, scratch.allocator);
    argv[argvCount - 1] = null;

    const(char)** environment;
    const environmentError = buildEnvironment(
        command.environment_,
        scratch.allocator,
        cast(const(char)**) environ,
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

    NativeSpawn spawnState;
    OsError error = spawnState.prepare(
        options,
        stdinDescriptor,
        stdoutDescriptor,
        stderrDescriptor,
        workingDirectory,
    );
    if (error.failed)
        return ProcessError(error, ProcessOperation.spawn);

    int processId;
    if (command.lookup_ == ExecutableLookup.searchPath &&
        !command.executable_.contains('/'))
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

version (linux) private struct NativeSpawn
{
nothrow @nogc:

    import core.sys.posix.spawn : posix_spawn_file_actions_t,
        posix_spawnattr_t;

    private posix_spawn_file_actions_t actions;
    private posix_spawnattr_t attributes;
    private bool actionsActive;
    private bool attributesActive;
    private int[3] stagedDescriptors = [-1, -1, -1];

    @disable this(this);

    ~this()
    {
        import core.sys.posix.spawn : posix_spawn_file_actions_destroy,
            posix_spawnattr_destroy;
        import core.sys.posix.unistd : nativeClose = close;

        foreach (descriptor; stagedDescriptors)
        {
            if (descriptor >= 0)
                nativeClose(descriptor);
        }
        if (actionsActive)
            posix_spawn_file_actions_destroy(&actions);
        if (attributesActive)
            posix_spawnattr_destroy(&attributes);
    }

    OsError prepare(
        scope const(SpawnOptions) options,
        int stdinDescriptor,
        int stdoutDescriptor,
        int stderrDescriptor,
        const(char)* workingDirectory,
    ) @system
    {
        import core.sys.posix.fcntl : O_RDONLY, O_WRONLY;
        import core.sys.posix.signal : sigemptyset, sigset_t;
        import core.sys.posix.spawn : POSIX_SPAWN_SETPGROUP,
            POSIX_SPAWN_SETSIGMASK, posix_spawn_file_actions_adddup2,
            posix_spawn_file_actions_addopen, posix_spawn_file_actions_init,
            posix_spawnattr_init, posix_spawnattr_setflags,
            posix_spawnattr_setpgroup, posix_spawnattr_setsigmask;

        int code = posix_spawn_file_actions_init(&actions);
        if (code != 0)
            return fromErrno(code);
        actionsActive = true;
        code = posix_spawnattr_init(&attributes);
        if (code != 0)
            return fromErrno(code);
        attributesActive = true;

        short flags;
        if (options.signalMask == SignalMaskPolicy.clear)
        {
            sigset_t emptyMask;
            sigemptyset(&emptyMask);
            code = posix_spawnattr_setsigmask(&attributes, &emptyMask);
            if (code != 0)
                return fromErrno(code);
            flags |= POSIX_SPAWN_SETSIGMASK;
        }
        if (options.isolation == ProcessIsolation.isolatedTree)
        {
            code = posix_spawnattr_setpgroup(&attributes, 0);
            if (code != 0)
                return fromErrno(code);
            flags |= POSIX_SPAWN_SETPGROUP;
        }
        code = posix_spawnattr_setflags(&attributes, flags);
        if (code != 0)
            return fromErrno(code);

        if (options.stdin.kind_ == RouteKind.nullDevice)
            code = posix_spawn_file_actions_addopen(
                &actions, 0, "/dev/null".ptr, O_RDONLY, 0,
            );
        else if (stdinDescriptor >= 0)
            code = addDescriptor(stdinDescriptor, 0, 0);
        if (code != 0)
            return fromErrno(code);

        if (options.stdout.kind_ == RouteKind.nullDevice)
            code = posix_spawn_file_actions_addopen(
                &actions, 1, "/dev/null".ptr, O_WRONLY, 0,
            );
        else if (stdoutDescriptor >= 0)
            code = addDescriptor(stdoutDescriptor, 1, 1);
        if (code != 0)
            return fromErrno(code);

        if (options.stderr.kind_ == RouteKind.nullDevice)
            code = posix_spawn_file_actions_addopen(
                &actions, 2, "/dev/null".ptr, O_WRONLY, 0,
            );
        else if (options.stderr.kind_ == RouteKind.mergeWithStdout)
            code = posix_spawn_file_actions_adddup2(&actions, 1, 2);
        else if (stderrDescriptor >= 0)
            code = addDescriptor(stderrDescriptor, 2, 2);
        if (code != 0)
            return fromErrno(code);

        if (workingDirectory !is null)
        {
            code = addChdir(&actions, workingDirectory);
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
        int* output,
    ) @system
    {
        import core.sys.posix.spawn : posix_spawn;
        import core.sys.posix.sys.types : pid_t;

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
        *output = cast(int) processId;
        return OsError.init;
    }

    private int addDescriptor(int descriptor, int target, size_t index) @system
    {
        import core.sys.posix.fcntl : fcntl;
        import core.sys.posix.spawn : posix_spawn_file_actions_adddup2;

        enum F_DUPFD_CLOEXEC = 1030;
        const staged = fcntl(descriptor, F_DUPFD_CLOEXEC, 3);
        if (staged < 0)
            return lastError().nativeCode;
        stagedDescriptors[index] = staged;
        return posix_spawn_file_actions_adddup2(&actions, staged, target);
    }
}

version (linux) private extern (C) pragma(mangle,
    "posix_spawn_file_actions_addchdir_np")
int addChdir(void* actions, const(char)* path);

version (linux) private extern (C) pragma(mangle,
    "posix_spawn_file_actions_addclosefrom_np")
int addCloseFrom(void* actions, int from);

version (linux) private OsError spawnSearchPath(
    NativeSpawn* spawnState,
    String executable,
    const(char)** argv,
    const(char)** environment,
    Allocator* allocator,
    int* output,
) @system
{
    String path = environmentValue(environment, "PATH");
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

version (linux) private OsError buildEnvironment(
    scope const(Environment) environment,
    Allocator* allocator,
    const(char)** inherited,
    const(char)*** output,
) @system
{
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
    const(char)** result = allocator.allocate!(const(char)*)(capacity);
    bool* emitted = allocator.allocate!bool(environment.entries.length);
    if (environment.entries.length != 0)
        memset(emitted, 0, environment.entries.length * bool.sizeof);

    size_t length;
    foreach (i; 0 .. inheritedCount)
    {
        const original = fromCString(inherited[i]);
        const name = environmentEntryName(original);
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

version (linux) private const(char)* makeEnvironmentEntry(
    scope const(EnvironmentEntry) entry,
    Allocator* allocator,
) @system
{
    const length = entry.name.length + 1 + entry.value.length;
    char* result = allocator.allocate!char(length + 1);
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

version (linux) private size_t findEnvironmentEntry(
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

version (linux) private String environmentEntryName(String entry) @safe
{
    size_t length;
    while (length < entry.length && entry[length] != '=')
        ++length;
    return entry[0 .. length];
}

version (linux) private String environmentValue(
    const(char)** environment,
    String name,
) @system
{
    for (size_t i; environment[i]!is null; ++i)
    {
        const entry = fromCString(environment[i]);
        if (entry.length > name.length && entry[name.length] == '=' &&
            entry[0 .. name.length].equal(name))
            return entry[name.length + 1 .. $];
    }
    return String.init;
}

version (linux) private const(char)* copyCString(
    String source,
    Allocator* allocator,
) @system
{
    char* result = allocator.allocate!char(source.length + 1);
    if (source.length != 0)
        memmove(result, source.ptr, source.length);
    result[source.length] = '\0';
    return result;
}

version (linux) private OsError validateSigchldPolicy() @system
{
    import core.stdc.signal : SIG_IGN;
    import core.sys.posix.signal : SA_NOCLDWAIT, SIGCHLD, sigaction,
        sigaction_t;

    sigaction_t current;
    if (sigaction(SIGCHLD, null, &current) != 0)
        return lastError();
    if (current.sa_handler is SIG_IGN ||
        (current.sa_flags & SA_NOCLDWAIT) != 0)
        return OsError(OsErrorKind.invalidArgument, 0);
    return OsError.init;
}

version (linux) private WaitResult waitLinux(
    ChildProcess* child,
    bool nonBlocking,
) @system
{
    import core.stdc.errno : EINTR, errno;
    import core.sys.posix.sys.wait : WNOHANG, waitpid;

    int nativeStatus;
    int result;
    do
        result = waitpid(child.processId_, &nativeStatus,
            nonBlocking ? WNOHANG : 0);
    while (result < 0 && errno == EINTR);
    if (result < 0)
        return WaitResult(
            ProcessError(lastError(), ProcessOperation.wait),
            WaitState.running,
            ExitStatus.init,
        );
    if (result == 0)
        return WaitResult(ProcessError.init, WaitState.running,
            ExitStatus.init);

    child.processId_ = -1;
    ExitStatus status;
    if (nativeExited(nativeStatus))
        status = ExitStatus(
            ExitKind.exited,
            cast(u32) nativeExitCode(nativeStatus),
            false,
        );
    else if (nativeSignaled(nativeStatus))
        status = ExitStatus(
            ExitKind.signaled,
            cast(u32) nativeTerminationSignal(nativeStatus),
            (nativeStatus & 0x80) != 0,
        );
    else
        return WaitResult(
            ProcessError(
                OsError(OsErrorKind.system, 0),
                ProcessOperation.wait,
        ),
        WaitState.running,
        ExitStatus.init,
        );
    return WaitResult(ProcessError.init, WaitState.exited, status);
}

// Linux exposes these as C preprocessor macros. Repeating the stable waitpid
// status encoding here avoids depending on runtime helper symbols in BetterC.
version (linux) private bool nativeExited(int status) pure @safe
{
    return (status & 0x7f) == 0;
}

version (linux) private bool nativeSignaled(int status) pure @safe
{
    const signal = status & 0x7f;
    return signal != 0 && signal != 0x7f;
}

version (linux) private int nativeExitCode(int status) pure @safe
{
    return (status >> 8) & 0xff;
}

version (linux) private int nativeTerminationSignal(int status) pure @safe
{
    return status & 0x7f;
}

version (linux) private WaitResult waitForLinux(
    ChildProcess* child,
    Timeout timeout,
) @system
{
    import core.stdc.errno : EINVAL, ENOSYS, EPERM;

    u64 started;
    OsError error = monotonicNanoseconds(&started);
    if (error.failed)
        return waitError(error);
    const duration = timeout.duration.totalNanoseconds;
    const deadline = duration > u64.max - started
        ? u64.max : started + duration;

    const descriptor = nativePidfdOpen(child.processId_, 0);
    if (descriptor >= 0)
    {
        const result = waitOnPidfd(child, descriptor, deadline);
        closeNativeDescriptor(descriptor);
        return result;
    }

    error = lastError();
    if (error.nativeCode != ENOSYS && error.nativeCode != EINVAL &&
        error.nativeCode != EPERM)
        return waitError(error);
    return waitByObservation(child, deadline);
}

version (linux) private WaitResult waitOnPidfd(
    ChildProcess* child,
    int descriptor,
    u64 deadline,
) @system
{
    import core.stdc.errno : EINTR, errno;
    import core.sys.posix.poll : POLLIN, pollfd;
    import core.sys.posix.time : timespec;

    pollfd event;
    event.fd = descriptor;
    event.events = POLLIN;
    for (;;)
    {
        u64 now;
        const clockError = monotonicNanoseconds(&now);
        if (clockError.failed)
            return waitError(clockError);
        if (now >= deadline)
            return tryWait(child);

        const remaining = deadline - now;
        timespec nativeTimeout;
        nativeTimeout.tv_sec = cast(typeof(nativeTimeout.tv_sec))(
            remaining / 1_000_000_000UL
        );
        nativeTimeout.tv_nsec = cast(typeof(nativeTimeout.tv_nsec))(
            remaining % 1_000_000_000UL
        );
        const result = nativePpoll(&event, 1, &nativeTimeout, null);
        if (result > 0)
            return waitLinux(child, false);
        if (result == 0)
            continue;
        if (errno != EINTR)
            return waitError(lastError());
    }
}

version (linux) private WaitResult waitByObservation(
    ChildProcess* child,
    u64 deadline,
) @system
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

version (linux) private WaitResult waitError(OsError error) pure @safe
{
    return WaitResult(
        ProcessError(error, ProcessOperation.wait),
        WaitState.running,
        ExitStatus.init,
    );
}

version (linux) private extern (C) pragma(mangle, "pidfd_open")
int nativePidfdOpen(int processId, uint flags);

version (linux) private extern (C) pragma(mangle, "ppoll")
int nativePpoll(void* descriptors, size_t count, const(void)* timeout,
    const(void)* signalMask);

version (linux) private void closeNativeDescriptor(int descriptor) @system
{
    import core.sys.posix.unistd : nativeClose = close;

    nativeClose(descriptor);
}

version (linux) private ProcessError signalLinux(
    scope const(ChildProcess)* child,
    int signal,
    ProcessOperation operation,
) @system
{
    import core.sys.posix.signal : nativeKill = kill;

    const target = child.isolation_ == ProcessIsolation.isolatedTree
        ? -child.processId_ : child.processId_;
    return nativeKill(target, signal) == 0
        ? ProcessError.init : ProcessError(lastError(), operation);
}

private void forceSignal(ChildProcess* child) @system
{
    version (linux)
    {
        import core.sys.posix.signal : SIGKILL;

        cast(void) signalLinux(child, SIGKILL, ProcessOperation.kill);
    }
}

private void reapIgnoringErrors(ChildProcess* child) @system
{
    version (linux)
    {
        cast(void) waitLinux(child, false);
        child.processId_ = -1;
    }
    else
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
