# Process library design specification

## Status and scope

This document is the implementation contract for the BetterC process library.
It is prescriptive. The archived `archive/betterc_process.d` file is research
input only; it is not a source file, public API, or compatibility target.

The first native backend targets Linux. Every public module must still compile
on unsupported targets and return `OsErrorKind.unsupported` without partially
initializing an output. A Windows backend is part of the architecture, but it
must not be claimed until its overlapped-pipe and handle-inheritance behavior
has dedicated tests.

The library belongs under `xtb.os`: creating, observing, and communicating with
processes is operating-system work. It must remain compatible with `-betterC`
and must not use the GC, exceptions, classes, runtime reflection, module
constructors, hidden heap allocation, or mutable process-wide library state.

## Goals

The library must provide both of these layers:

1. A small, reliable low-level API for pipes, direct process creation, explicit
   standard-stream routing, waiting, termination, and manual communication.
2. Owning convenience operations for the common spawn/capture/wait and linear
   pipeline cases. Convenience may allocate only through an allocator supplied
   at the call site.

The low-level layer must not be made awkward merely to support the convenience
layer. In particular, a caller can always spawn a child, obtain its pipe ends,
and drive them from its own event loop.

The following properties are mandatory:

- command arguments remain separate values from end to end;
- no direct-command API parses a shell command line;
- ownership transfer and borrowed lifetimes are visible;
- all descriptors/handles are close-on-exec or non-inheritable at creation;
- a child inherits only the handles explicitly selected by its spawn spec;
- output capture cannot deadlock merely because one stream or its buffer fills;
- timeout, nonzero exit, signal termination, EOF, would-block, and truncation are
  ordinary states rather than exceptions or assertions;
- partial spawn and pipeline failures close every created handle and reap every
  child that the library started;
- scratch storage comes from the installed thread context and never appears as
  a fallible byte-buffer parameter;
- all size arithmetic is checked before the arithmetic is evaluated; and
- platform-specific behavior is isolated behind narrow backend modules.

## Non-goals for the first implementation

- A general shell language or command-string parser.
- Pseudoterminals, terminal job control, user/group/credential changes,
  namespaces, seccomp, or arbitrary pre-exec callbacks.
- Arbitrary DAG pipelines. The low-level pipe and spawn APIs are sufficient to
  construct them explicitly.
- A background reaper thread or SIGCHLD handler installed by the library.
- Detaching an already spawned direct child.
- A portable promise that killing one process kills every descendant unless an
  isolated process-tree option was selected and supported.
- Text decoding of stdout/stderr. Process output is bytes.

Unsupported features must be absent or return `unsupported`; they must not be
approximated with unsafe semantics.

## Findings from the archived prototype

The archive contains useful product-level ideas:

- direct argv execution and shell execution are visibly separate;
- low-level pipes, managed children, one-shot execution, and pipelines form a
  sensible progression;
- supplied handles are preserved on spawn failure;
- simultaneous stdin/stdout/stderr pumping avoids the classic pipe deadlock;
- bounded capture records truncation and continues draining; and
- pipeline creation attempts cleanup when a later stage fails.

Those ideas should survive. The archived implementation itself should not.
Important problems include:

- It does not compile with the pinned LDC. The declaration
  `const(char)[] const[] arguments` is invalid D syntax.
- It is one 5,779-line Linux-only module and deliberately fails compilation on
  every other target. This defeats the existing package boundaries and
  unsupported-backend policy.
- It spells ordinary strings as raw `const(char)[]` and duplicates `OsError`,
  timeout, formatting, checked arithmetic, and scratch facilities already
  owned elsewhere in the project.
- It asks callers to calculate and pass untyped scratch byte buffers. That is
  contrary to the explicit TLS thread-context design, makes temporary capacity
  an expected API failure, and exposes backend implementation details.
- Its pipe owners disable copying but have no destructors. Its process owner
  can be dropped while still carrying a POSIX reap obligation, leaving a
  zombie. Hand-written `takeX` functions also accept null and silently return
  empty owners instead of using the project's move and pointer contracts.
- It creates a pipe and sets `FD_CLOEXEC` in a second `fcntl` call. Another
  thread can spawn between those calls and leak the descriptor into an
  unrelated child. Linux must use `pipe2(O_CLOEXEC)` and atomic close-on-exec
  duplication.
- It uses `fork` and then performs path search, string operations, signal setup,
  directory changes, descriptor work, and error reporting before `execve`.
  That child-side region is too large to audit as async-signal-safe in a
  multithreaded process. The normal backend must use `posix_spawn`.
- It silently changes the blocking flag on caller-visible pipe descriptions
  during communication and later restores it. Duplicated descriptors share
  those flags, so another owner or thread can observe the temporary change.
- Its monotonic clock helper converts clock failure to timestamp zero and its
  timed wait wakes every millisecond. Clock failure must remain an error and
  waiting must use a kernel wait primitive where available.
- Several supposedly checked expressions overflow before reaching the checked
  helper, including counts such as `arguments.length + 2` and string lengths
  such as `source.length + 1`.
- Its pipeline is called transactional even though an early stage can execute
  externally visible side effects before a later stage fails to spawn. Resource
  rollback can be guaranteed; rollback of program effects cannot.
- Its pipeline process-group option creates a separate group per stage while
  its prose suggests a pipeline policy. The ownership and descendant-kill
  semantics need to be stated explicitly.
- The embedded tests cover only a few happy paths. They do not establish
  handle-leak safety, allocation failure, invalid input, exec failure, timeout,
  simultaneous full pipes, cleanup, signal interaction, or pipeline rollback.

## Module organization

Use focused public modules and private/package backend modules:

```text
source/xtb/os/
├── pipe.d                    # PipeReader/PipeWriter and byte I/O
├── process.d                 # commands, routes, ChildProcess, spawn/wait
├── process_io.d              # communicate and one-shot run
├── pipeline.d                # owning linear pipelines and one-shot pipeline
├── process_native.d          # explicitly platform-specific escape hatches
└── process_backend/
    ├── linux.d               # package-private native implementation
    ├── windows.d             # package-private when implemented
    └── unsupported.d         # compile-preserving stub
```

`xtb.os` publicly re-exports the stable surface from `pipe`, `process`,
`process_io`, and `pipeline`. It must not re-export the native escape-hatch
module. Backends may import selected `core.stdc`/`core.sys` bindings; public
policy modules must not expose native types.

Do not create all of these files as placeholders. Add each file with the first
coherent implementation that belongs in it.

## Common API conventions

Production modules establish truthful common attributes at module or aggregate
scope instead of repeating `nothrow @nogc` on every declaration. Foreign calls
and native handle arithmetic stay in small `@system` functions; validated
value helpers should be `@safe` and `pure` where possible.

Required mutable pointers panic when null. An output owner that must be empty
on entry also panics when it is already live. Invalid enum values arriving from
untrusted data produce an explicit `invalidArgument` error when validation is
part of the operation. Internal impossible states panic.

Read-only text is always `String`. Commands and environment descriptions are
borrowed simple values. Their text and outer slices must remain alive until the
spawn operation returns; the spawned process never borrows D memory. Output is
`u8[]`/`Array!u8`, not `StringBuf`, because a child may emit arbitrary binary
bytes including invalid UTF-8 and NUL.

Copyable borrowed descriptions and policy values are passed as
`scope const(T)` values. This includes `Command`, `SpawnOptions`,
`CommunicateOptions`, `RunOptions`, `PipelineSpec`, and `PipelineRunOptions`.
Their copies are shallow descriptors, and `scope` prevents their referenced
data from escaping. Do not expose a required `const(T)*` merely to avoid this
small copy: it introduces meaningless nullability and forces `&value` at a
call site where no mutation occurs. The native ABI remains free to lower a
value argument indirectly.

The project does not use `in` as shorthand for this contract. Modern `in`
acquires scope semantics only with `-preview=in`, while this project currently
enables DIP1000 without that separate preview. Spelling `scope const(T)` keeps
the source-level lifetime contract explicit and independent of compiler
argument-passing choices.

Pointers remain appropriate for mutable outputs/state transitions, optional
objects, the intrusive `Allocator*` handle, accessors returning an interior
owner, and borrowed non-copyable resource identity. For example,
`scope const(ChildProcess)*` may identify the one owned native process for a
non-consuming signal operation; copying a `ChildProcess` value is forbidden.

Mutating UFCS operations may use `ref` only for their first owning receiver.
Other mutations, including process state transitions, use pointers so the call
site makes consumption visible:

```d
WaitResult waited = waitFor(&child, Timeout.after(milliseconds(500)));
ProcessError error = terminateAndWait(&child, &status);
```

Options are ordinary copyable policy values, not separate builder owners.
Every options type has a useful `.init`, and commonly useful presets may be
static factories such as `RunOptions.capture()`. Free UFCS transformations take
an options value, modify its copy, and return that copy:

```d
RunOptions options = RunOptions.capture()
    .withTimeout(milliseconds(2_000))
    .withCaptureLimit(mebibytes(4))
    .mergingStderr();
```

These transformations are allocation-free and cannot accumulate a hidden
error. Public fields remain available for direct aggregate construction and
unusual combinations. Do not introduce a stateful `RunOptionsBuilder`, sticky
validity flag, required finalization call, or setters that mutate a temporary
through a pointer.

## Errors and expected states

Do not introduce a second generic `Status` or `Result`. Extend the shared
`OsErrorKind` only where the distinction is useful to every OS resource. The
process work requires at least `resourceExhausted`, `brokenPipe`, and
`invalidEncoding` in addition to the existing categories. A deadline expiring
is normally a result state, not `OsErrorKind.timedOut`.

Process operations add context without duplicating the native error:

```d
enum ProcessOperation : ubyte
{
    none,
    validate,
    createPipe,
    configurePipe,
    spawn,
    wait,
    communicate,
    terminate,
    pipelineSpawn,
    pipelineWait,
}

enum noStageIndex = size_t.max;

struct ProcessError
{
    OsError os;
    ProcessOperation operation;
    size_t stageIndex = noStageIndex;

    bool failed() const pure @safe;
    bool succeeded() const pure @safe;
}
```

`nativeCode` remains captured in `OsError`. `stageIndex` is set only for a
pipeline stage. Error formatting composes with the existing `Writer`/printing
layer; it writes into caller storage or a caller-owned `StringBuf` and performs
no hidden allocation.

The following are not process-operation errors:

- a child exits with a nonzero code;
- a child is terminated by a signal;
- a nonblocking pipe would block;
- a pipe reaches EOF or its peer closes;
- a wait deadline expires while the child remains live; and
- a capture limit truncates output while the library continues draining.

Each fallible constructor has a strong ownership guarantee. Unless an API is
explicitly documented as progressive, an error leaves the output at `.init`
and leaves every borrowed or caller-owned input untouched.

## Timeouts

Process waiting uses the finite, nonnegative `Duration` from
`xtb.core.duration`. Extend `xtb.os.time` with a tagged policy value whose zero
state means infinite; do not assign a sentinel meaning to `Duration.init` or
use a `duration + infinite bool` pair:

```d
enum TimeoutKind : ubyte
{
    infinite,
    immediate,
    finite,
}

struct Timeout
{
    private TimeoutKind kind_;
    private Duration duration_;

    static Timeout infinite() pure @safe;
    static Timeout immediate() pure @safe;
    static Timeout after(Duration duration) pure @safe;
}
```

`Timeout.init` and `Timeout.infinite` are equivalent. `Timeout.immediate`
requests one nonblocking observation. `Timeout.after(Duration.init)` is
normalized to `Timeout.immediate`; a finite timeout therefore always contains
a nonzero `Duration`. Accessors expose the kind and require the finite state
before returning its duration.

A finite timeout is relative to entry into the operation. The backend converts
it once to a monotonic absolute deadline, saturating only the deadline addition
after explicitly checking overflow. Failure to read the monotonic clock is an
error. Repeated `EINTR` processing recomputes the remaining duration against
the same deadline, so signals cannot extend the timeout.

Unit conversion belongs only to the core helpers such as `milliseconds`;
`Timeout` must not duplicate those factories.

## Pipes

`PipeReader` and `PipeWriter` are distinct, non-copyable explicit-lifetime
owners. Their zero states are closed. `deinit` performs mechanical descriptor
cleanup; ordinary scope exit does nothing. `Pipe` owns one of each and is also
explicit-lifetime. Explicit `close` reports an error, while `deinit` performs
best-effort cleanup when the error is intentionally discarded.

```d
enum PipeMode : ubyte
{
    blocking,
    nonBlocking,
}

struct PipeOptions
{
    PipeMode readerMode;
    PipeMode writerMode;
}

OsError createPipe(PipeOptions options, Pipe* output);
OsError close(PipeReader* reader);
OsError close(PipeWriter* writer);
PipeReadResult readSome(PipeReader* reader, u8[] output);
PipeWriteResult writeSome(PipeWriter* writer, scope const(u8)[] input);
```

The library always creates native handles with close-on-exec/non-inheritable
state atomically. There is no option to disable this. Child inheritance occurs
only through a spawn mapping.

Read and write results contain `OsError`, a transferred count, and a state.
Read states are `data`, `endOfFile`, and `wouldBlock`; write states are `data`,
`peerClosed`, and `wouldBlock`. An empty destination/source returns zero data
without probing EOF. `readAll` and `writeAll` report partial progress and never
reinterpret would-block as an invalid object.

POSIX writes must not let `SIGPIPE` terminate the application. The backend
temporarily blocks SIGPIPE only in the calling thread, preserves the previous
mask and any previously pending SIGPIPE, consumes only the signal generated by
its own failed write, and restores the mask on every path. It must never change
the process-wide SIGPIPE disposition.

Duplicating an endpoint produces a new owner of the same underlying stream.
The docs must state that duplicated endpoints share native file-description
flags, multiple readers compete for bytes, multiple writers delay EOF, and
duplication is not broadcasting. Communication helpers never change blocking
mode behind the caller's back. A process pipe is created close-on-exec with
both ends initially blocking, then only the parent-owned end is made
nonblocking before spawn. The opposite end mapped onto the child's standard
stream remains blocking. Manually created pipes use the requested per-end
mode.

Portable readiness is part of the low-level layer rather than an implementation
detail of `communicate`:

```d
enum PipeEvent : ubyte
{
    readable,
    writable,
    hangup,
    error,
}

alias PipeEvents = FlagSet!PipeEvent;

struct PipePollItem
{
    static PipePollItem forReader(PipeReader* reader, PipeEvents interests);
    static PipePollItem forWriter(PipeWriter* writer, PipeEvents interests);

    PipeEvents events;
}

OsError pollPipes(
    scope PipePollItem[] items,
    Timeout timeout,
    size_t* readyCount,
);
```

The tagged constructors prevent an item from containing both or neither
endpoint. `pollPipes` obtains its native poll array from internal scratch,
clears every output event before polling, retries `EINTR` against the original
deadline, and treats timeout as successful readiness count zero. Native event
loops use the explicit native escape-hatch module instead.

## Command descriptions

`Command` is a borrowed value, not an owning builder:

```d
enum ExecutableLookup : ubyte
{
    exact,
    searchPath,
}

struct Command
{
    private String executable_;
    private const(String)[] arguments_;
    private String argumentZero_;
    private Option!Path workingDirectory_;
    private Environment environment_;
    private ExecutableLookup lookup_;

    static Command exact(Path executable, const(String)[] arguments = null);
    static Command search(String executable, const(String)[] arguments = null);
}
```

`arguments` excludes `argv[0]`. By default, `argv[0]` uses the executable text
as supplied by the caller. A named setter can override it for the uncommon
case. Free mutating setters use the permitted `ref Command` UFCS receiver:

```d
command.setArguments(arguments[]);
command.setWorkingDirectory(path);
command.clearWorkingDirectory();
command.setArgumentZero("tool-name");
command.setEnvironment(environment);
```

These setters borrow; they do not allocate or retain temporary scratch.
The constructors likewise retain the argument slice, so that parameter cannot
be `scope`; callers keep it alive until spawn returns.
`validate(Command)` is available when an application wants to diagnose a
configuration before spawning. Spawn validates again.

An exact executable does not search `PATH`, even if its spelling contains no
separator. A searched executable containing a native path separator is treated
as exact. Search uses `PATH` from the effective child environment, not
accidentally from a different parent snapshot. A missing `PATH` uses the
backend's documented system default; an empty component means the child
working directory on POSIX. Candidate execution is attempted directly—never
pre-checked with `access()`—and `ENOEXEC` never invokes a shell implicitly.

POSIX accepts native path/argument bytes except NUL. Windows converts valid
UTF-8 to UTF-16 and returns `invalidEncoding` for malformed input. The Windows
backend passes an explicit application name to `CreateProcessW` and applies a
single documented inverse-`CommandLineToArgvW` quoting algorithm to arguments.
It must never concatenate unquoted input and ask Windows to guess the program.

## Environments

```d
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
```

`.init` inherits unchanged. `replace` starts empty; `overlay` starts from a
snapshot of the current environment. Names must be nonempty and contain
neither NUL nor `=`. Values may be empty but not contain NUL. A remove entry
must have an empty value. Duplicate effective names are rejected instead of
using an undocumented first/last-wins rule. Name comparison follows the target
environment rules and is documented by the backend.
`inherit` rejects nonempty entries instead of silently ignoring them; use
`overlay` to modify the inherited environment.

Reading the process environment is inherently shared state. On POSIX, callers
must not mutate `environ` concurrently with an inherit/overlay spawn. The
library takes no global environment lock because it could not coordinate with
foreign code using libc directly. `replace` with fully caller-owned entries is
the deterministic option.

## Standard-stream routes

Use direction-specific route types so invalid combinations are not easy to
construct:

```d
struct InputRoute
{
    static InputRoute inherited();
    static InputRoute nullDevice();
    static InputRoute piped();
    static InputRoute borrow(File* file);
    static InputRoute borrow(PipeReader* reader);
}

struct OutputRoute
{
    static OutputRoute inherited();
    static OutputRoute nullDevice();
    static OutputRoute piped();
    static OutputRoute borrow(File* file);
    static OutputRoute borrow(PipeWriter* writer);
}

struct ErrorRoute
{
    static ErrorRoute inherited();
    static ErrorRoute nullDevice();
    static ErrorRoute piped();
    static ErrorRoute borrow(File* file);
    static ErrorRoute borrow(PipeWriter* writer);
    static ErrorRoute mergeWithStdout();
}
```

All `.init` routes inherit. `piped` returns the complementary parent endpoint
inside `ChildProcess`. A borrowed file/pipe remains owned by the caller and
must stay open until spawn returns. Spawn duplicates/maps it for the child and
never conditionally consumes it. This single rule replaces the archive's
`SpawnIo` transfer protocol and makes failure behavior obvious. Callers that no
longer need an endpoint close it explicitly after successful spawn.

## Child process ownership

`ChildProcess` owns a direct-child reap obligation plus any parent pipe ends
created by its routes. It is non-copyable and movable. `.init` is empty.

```d
struct ChildProcess
{
    @disable this(this);
    @disable ref ChildProcess opAssign(ChildProcess source) return;

    bool ownsProcess() const pure @safe;
    bool empty() const pure @safe;
    ProcessId id() const pure @safe;
    PipeWriter* stdinPipe() return;
    PipeReader* stdoutPipe() return;
    PipeReader* stderrPipe() return;
    void deinit();
}
```

`ChildProcess` has no destructor-driven lifecycle policy. A caller must resolve
the semantic process obligation explicitly with `wait`, `communicate`,
`killAndWait`, `terminateAndWait`, or another operation that reaps the direct
child. Only after that resolution does `deinit` perform mechanical cleanup of
remaining parent-side pipes/local state. Checked builds reject `deinit` while
the child is still owned and unreaped. Generic cleanup must never silently
decide to kill, wait for, or detach a process.

There is no `releasePid` or `detach(ChildProcess*)`. A caller that wants a
background process must use a future dedicated detached-spawn operation whose
backend establishes that lifetime before returning.

POSIX users must not set `SIGCHLD` to `SIG_IGN`, use `SA_NOCLDWAIT`, or reap a
library-owned PID from an unrelated `waitpid(-1, ...)` handler/thread. Spawn
detects incompatible SIGCHLD disposition when practical and returns an
explicit error before creation. The application owns synchronization around
any later signal-policy changes.

## Spawning, waiting, and termination

```d
enum ProcessIsolation : ubyte
{
    direct,
    isolatedTree,
}

enum SignalMaskPolicy : ubyte
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

SpawnOptions withStdin(SpawnOptions options, InputRoute route) pure @safe;
SpawnOptions withStdout(SpawnOptions options, OutputRoute route) pure @safe;
SpawnOptions withStderr(SpawnOptions options, ErrorRoute route) pure @safe;
SpawnOptions withIsolation(
    SpawnOptions options,
    ProcessIsolation isolation,
) pure @safe;
SpawnOptions withSignalMask(
    SpawnOptions options,
    SignalMaskPolicy policy,
) pure @safe;

ProcessError spawn(
    scope const(Command) command,
    scope const(SpawnOptions) options,
    ChildProcess* output,
);

WaitResult tryWait(ChildProcess* child);
WaitResult waitFor(ChildProcess* child, Timeout timeout);
ProcessError wait(ChildProcess* child, ExitStatus* output);
ProcessError requestTermination(scope const(ChildProcess)* child);
ProcessError kill(scope const(ChildProcess)* child);
ProcessError terminateAndWait(ChildProcess* child, ExitStatus* output);
ProcessError killAndWait(ChildProcess* child, ExitStatus* output);
```

`SpawnOptions.init` inherits standard streams, creates a direct process, and
clears a transient calling-thread signal mask in the executed image. Selecting
`SignalMaskPolicy.inherit` preserves it deliberately. Required output pointers
and a nonempty destination are contract violations. Command validation and
native spawn failures are recoverable `ProcessError` values.

`tryWait` and a timed-out `waitFor` leave the process owned. A successful wait
reaps it and clears only the process obligation; buffered stdout/stderr pipe
ends may still be read. `wait` should not be called while undrained piped output
can fill. `communicate` is the normal operation in that case.

`ExitStatus` distinguishes normal exit from signal termination and preserves
the full native unsigned exit code where the platform provides one. Helper
queries such as `succeeded`, `exited`, `signaled`, `exitCode`, and
`terminationSignal` validate the active state rather than exposing a union
incorrectly. A nonzero code never changes `ProcessError`.

```d
enum ExitKind : ubyte
{
    exited,
    signaled,
}

struct ExitStatus
{
    private ExitKind kind_;
    private u32 code_;
    private bool coreDumped_;
}
```

On Windows every ordinary completion is `exited`; the backend preserves the
full 32-bit process exit code. POSIX signal numbers occupy `code_` only when
`kind_ == ExitKind.signaled`.

`requestTermination` is cooperative (`SIGTERM` on POSIX); `kill` is forceful.
Neither consumes the wait obligation. The `...AndWait` operations do. With
`isolatedTree`, termination targets the owned process group/job as well as
waiting for the direct child. Without isolation, descendant behavior is not
promised.

## Communication

The managed communication primitive simultaneously writes stdin, drains
stdout, drains stderr, and observes process completion. It never writes all
stdin before reading output and never waits for exit before draining output.

```d
struct CaptureBuffer
{
    u8[] storage;
    size_t length;
    bool truncated;

    u8[] bytes() return @system;
    const(u8)[] bytes() const return @system;
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
) pure @safe;
CommunicateOptions withoutTimeout(CommunicateOptions options) pure @safe;
CommunicateOptions withTimeoutAction(
    CommunicateOptions options,
    TimeoutAction action,
) pure @safe;
CommunicateOptions withTerminationGrace(
    CommunicateOptions options,
    Duration duration,
) pure @safe;

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
);
```

A null capture means drain and discard when that pipe exists. The input slice
and both complete capture-storage slices must not overlap; stdout and stderr
captures must also be distinct and non-overlapping. Rejecting aliasing prevents
captured output from overwriting input that has not yet reached the child.
When a capture fills, the helper marks it truncated and always continues
draining/discarding.
There is no `drainAfterTruncation = false` option: callers wanting backpressure
or early closure use the manual pipe API. Always draining is what makes the
convenience contract safe.

On `leaveRunning`, partial buffer lengths and `inputWritten` remain valid, the
child retains every still-open owner, and the caller can invoke communicate
again with the unconsumed input suffix. On a completing timeout action, the
helper closes stdin, applies the selected process/tree termination policy,
closes output ends after draining what is immediately available, and reaps the
direct child. A timeout result is success at the operation layer and has a
distinct state.

Communication uses parent endpoints made nonblocking before spawn while each
child endpoint remains blocking. It does not temporarily alter shared flags.
Linux waits on all active pipe descriptors and a pidfd when available; the
fallback combines `poll` with targeted `waitpid` checks against one absolute
deadline. It must not use an unconditional 1 ms or 10 ms wakeup loop.

## One-shot convenience

The owning convenience result stores bytes, not text:

```d
enum RunState : ubyte
{
    exited,
    timedOut,
}

enum RunInputMode : ubyte
{
    provided,
    inherited,
    nullDevice,
}

enum RunOutputMode : ubyte
{
    capture,
    inherited,
    discard,
}

enum RunErrorMode : ubyte
{
    capture,
    inherited,
    discard,
    mergeWithStdout,
}

struct RunOutput
{
    @disable this(this);

    RunState state;
    ExitStatus exitStatus;
    Array!u8 stdout;
    Array!u8 stderr;
    bool stdoutTruncated;
    bool stderrTruncated;
    size_t inputWritten;

    void deinit();
}

struct RunOptions
{
    Timeout timeout = Timeout.init;
    RunInputMode stdinMode = RunInputMode.provided;
    RunOutputMode stdoutMode = RunOutputMode.capture;
    RunErrorMode stderrMode = RunErrorMode.capture;
    size_t maxStdoutBytes = 16 * 1024 * 1024;
    size_t maxStderrBytes = 16 * 1024 * 1024;
    ProcessIsolation isolation = ProcessIsolation.isolatedTree;
    TimeoutAction timeoutAction = TimeoutAction.kill;
    Duration terminationGrace;

    static RunOptions capture() pure @safe;
    static RunOptions inherited() pure @safe;
}

RunOptions withTimeout(RunOptions options, Duration duration) pure @safe;
RunOptions withoutTimeout(RunOptions options) pure @safe;
RunOptions withInputMode(RunOptions options, RunInputMode mode) pure @safe;
RunOptions withOutputMode(RunOptions options, RunOutputMode mode) pure @safe;
RunOptions withErrorMode(RunOptions options, RunErrorMode mode) pure @safe;
RunOptions withCaptureLimit(RunOptions options, size_t bytes) pure @safe;
RunOptions withStdoutLimit(RunOptions options, size_t bytes) pure @safe;
RunOptions withStderrLimit(RunOptions options, size_t bytes) pure @safe;
RunOptions withIsolation(
    RunOptions options,
    ProcessIsolation isolation,
) pure @safe;
RunOptions withTimeoutAction(
    RunOptions options,
    TimeoutAction action,
) pure @safe;
RunOptions withTerminationGrace(
    RunOptions options,
    Duration duration,
) pure @safe;
RunOptions mergingStderr(RunOptions options) pure @safe;

ProcessError run(
    scope const(Command) command,
    scope const(u8)[] input,
    scope const(RunOptions) options,
    Allocator* allocator,
    RunOutput* output,
);

RunOutput runOrPanic(
    scope const(Command) command,
    scope const(u8)[] input,
    scope const(RunOptions) options,
    Allocator* allocator,
);
```

`RunInputMode` supports provided input, inherited stdin, and the null device.
`RunOutputMode` supports capture, inherit, and discard. `RunErrorMode` supports
those three choices plus merge with stdout. `RunOptions.init` captures
stdout/stderr, supplies the provided input (an empty slice therefore sends
immediate EOF), uses an infinite timeout, limits each capture to 16 MiB, and
uses isolated-tree cleanup so a finite timeout cannot leave descendants holding
capture pipes. A caller must opt into unlimited capture by setting
`size_t.max`; no convenience API silently grows without a bound.

`RunOptions.capture()` is the explicit spelling of `.init` and
`RunOptions.inherited()` changes all three standard streams to inherited while
preserving the remaining safety defaults. `withCaptureLimit` applies the same
bound to stdout and stderr; the stream-specific variants allow asymmetric
bounds. `mergingStderr` selects `RunErrorMode.mergeWithStdout`. The timeout
action and grace transformations are separate because grace is ignored unless
the selected action performs cooperative termination before forceful cleanup.

`run` composes spawn and communicate and never returns a live child. On native
or allocation failure it kills/reaps any started child, destroys partial owned
output, and leaves `output` at `.init`. Nonzero exit, timeout, and truncation
produce a successful `ProcessError.init` with state in `RunOutput`.
`TimeoutAction.leaveRunning` is rejected before spawn by `run`; it is available
only to callers that already own a `ChildProcess` and call `communicate`.

`runOrPanic` panics only on a process-operation error. It does not panic merely
because the child exits unsuccessfully or times out. It exists for tools whose
only meaningful response to an unavailable executable or allocation failure is
fatal termination; library code should normally use `run`.

An explicit helper may expose captured bytes as a borrowed `String` for
diagnostic text, but it performs no UTF-8 validation and its name must state
that it is a view. The arrays remain the owners.

## Linear pipelines

Pipelines are a convenience over the same spawn/pipe primitives. A caller that
needs a graph uses those primitives directly.

```d
struct PipelineStage
{
    Command command;
    Option!ErrorRoute stderrOverride;
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

ProcessError spawnPipeline(
    scope const(PipelineStage)[] stages,
    scope const(PipelineOptions) options,
    Allocator* allocator,
    Pipeline* output,
);

ProcessError spawnPipeline(
    scope const(Command)[] commands,
    scope const(PipelineOptions) options,
    Allocator* allocator,
    Pipeline* output,
);

enum PipelineErrorMode : ubyte
{
    captureEach,
    inherited,
    discard,
}

struct PipelineRunOptions
{
    Timeout timeout = Timeout.init;
    RunInputMode stdinMode = RunInputMode.provided;
    RunOutputMode stdoutMode = RunOutputMode.capture;
    PipelineErrorMode stderrMode = PipelineErrorMode.captureEach;
    size_t maxStdoutBytes = 16 * 1024 * 1024;
    size_t maxStderrBytesPerStage = 16 * 1024 * 1024;
    PipelineSuccess success = PipelineSuccess.lastStage;
    ProcessIsolation isolation = ProcessIsolation.isolatedTree;
    TimeoutAction timeoutAction = TimeoutAction.kill;
    Duration terminationGrace;

    static PipelineRunOptions capture() pure @safe;
    static PipelineRunOptions inherited() pure @safe;
}

PipelineRunOptions withTimeout(
    PipelineRunOptions options,
    Duration duration,
) pure @safe;
PipelineRunOptions withoutTimeout(PipelineRunOptions options) pure @safe;
PipelineRunOptions withInputMode(
    PipelineRunOptions options,
    RunInputMode mode,
) pure @safe;
PipelineRunOptions withOutputMode(
    PipelineRunOptions options,
    RunOutputMode mode,
) pure @safe;
PipelineRunOptions withErrorMode(
    PipelineRunOptions options,
    PipelineErrorMode mode,
) pure @safe;
PipelineRunOptions withCaptureLimit(
    PipelineRunOptions options,
    size_t bytes,
) pure @safe;
PipelineRunOptions withStdoutLimit(
    PipelineRunOptions options,
    size_t bytes,
) pure @safe;
PipelineRunOptions withStderrLimitPerStage(
    PipelineRunOptions options,
    size_t bytes,
) pure @safe;
PipelineRunOptions withSuccessPolicy(
    PipelineRunOptions options,
    PipelineSuccess success,
) pure @safe;
PipelineRunOptions withIsolation(
    PipelineRunOptions options,
    ProcessIsolation isolation,
) pure @safe;
PipelineRunOptions withTimeoutAction(
    PipelineRunOptions options,
    TimeoutAction action,
) pure @safe;
PipelineRunOptions withTerminationGrace(
    PipelineRunOptions options,
    Duration duration,
) pure @safe;
```

These are the implemented slice-borrowing entry points. The `Command[]`
overload gives every stage the default stderr policy; use `PipelineStage[]`
only where one or more stages need an override. Both slices and all command
text remain borrowed only until `spawnPipeline` returns. The returned owner
contains native resources and allocator-owned child/status slots, but no
references to either description slice. Do not add the archive's sticky-error
`PipelineBuilder`.

The explicit argument arrays are intentionally retained for the first
slice-borrowing implementation, but they are not the intended final spelling
for fixed commands. A later allocation-free convenience layer should support:

```d
auto plan = pipeline(
    command("generate", "--count", "1000"),
    command("filter", "--matching", pattern),
    command("sort", "--stable"),
);
```

`command(String, arguments...)` means PATH lookup, while a `Path` executable
selects exact lookup. Its inferred wrapper owns a fixed array of `String`
descriptors but continues to borrow the characters. It must not store a slice
pointing into its own array, because copying such a self-referential value
would leave the slice aimed at the old object. Instead, `runPipeline` creates
temporary borrowed `Command` views at the operation boundary while the
scope-qualified wrappers remain alive.

Plain commands use default stage policy. An explicit `stage(command(...))`
wrapper is reserved for uncommon per-stage configuration such as a stderr
override. Do not use a shell-like string, overloaded `|`, a fixed-capacity
public `Command`, or hidden allocation to shorten the call site. Runtime-sized
programs continue using borrowed `Command[]`; a genuinely allocator-owned
dynamic command builder may be added separately if real call sites require
one. This convenience layer is deferred until after fixed-buffer communication
and slice-borrowing pipelines are complete.

`Pipeline` owns an allocator-backed array of child/process slots and exit
statuses plus the exposed first-stdin/final-stdout/stage-stderr endpoints. It
is a non-copyable explicit-lifetime owner. The caller must explicitly resolve
all stage lifecycle obligations before `deinit`; checked builds reject cleanup
while any stage remains unreaped. Failed pipeline construction is different: it
is an internal transactional rollback and explicitly terminates/reaps stages
that were started before a later construction failure. The low-level arbitrary-
graph path remains allocation-free; the linear-pipeline owner takes an explicit
allocator rather than retaining four parallel caller slices.

Pipeline creation has a strong resource guarantee: on failure it closes every
intermediate and exposed endpoint, terminates and reaps every successfully
started stage, resets its owned arrays, preserves all borrowed inputs, and
leaves the output empty. It must be documented as resource-transactional, not
execution-transactional. A stage that started before a later failure may have
already changed files, sent messages, or produced other side effects.

Intermediate parent pipe ends are closed immediately after the next stage is
successfully connected. EOF must never depend on a forgotten intermediate
writer in the parent. `tryWaitPipeline` observes every stage without blocking;
`waitPipeline` waits for every remaining stage and records exit statuses in
stage order. As with waiting on one child, it must not be called while exposed
stdout or a piped stage stderr can fill. The later managed pipeline
communication operation will pump first-stage stdin, final-stage stdout, and
every captured stderr stream concurrently.

`requestPipelineTermination`, `killPipeline`, and their `...AndWait` variants
target every still-live stage. Pipeline success is a query over the recorded
statuses: `lastStage` follows conventional shell behavior while `everyStage`
requires all stages to succeed.

On POSIX, isolated pipeline stages may each own an isolated process group when
forming one race-free common group is unavailable; cleanup then signals every
owned group. The public contract is tree cleanup for each stage, not a promise
that all stages share one native group identifier. Windows uses one job object
when supported.

The one-shot `runPipeline` mirrors `run`, but keeps its own options type because
captured stderr and success policy are stage-aware. `PipelineErrorMode` does
not have a merge-with-stdout state: merging an intermediate stage's stderr into
its stdout would corrupt the byte stream sent to the next stage. The captured
stderr limit applies independently to each stage, making the total worst-case
storage explicit from the stage count.

```d
struct PipelineStageOutput
{
    ExitStatus exitStatus;
    Array!u8 stderr;
    bool stderrTruncated;
}

struct PipelineOutput
{
    @disable this(this);

    RunState state;
    Array!u8 stdout;
    bool stdoutTruncated;
    size_t inputWritten;
    Array!PipelineStageOutput stages;

    void deinit();
}

ProcessError runPipeline(
    scope const(Command)[] commands,
    scope const(u8)[] input,
    scope const(PipelineRunOptions) options,
    Allocator* allocator,
    PipelineOutput* output,
);
```

`PipelineRunOptions.capture()` is equivalent to `.init`.
`PipelineRunOptions.inherited()` changes all standard streams to inherited.
`withCaptureLimit` applies its bound to final stdout and independently to each
stage's stderr; the two specific limit transformations allow asymmetric bounds.
The operation uses explicit output allocation, bounded capture, no live owner
on return, and an owning stage output for every input command. The pipeline
success policy is a query on those statuses; it is not a spawn/communication
error.

## Shell execution

Shell execution is never an overload of direct execution. If added, it belongs
in a separate `xtb.os.process_shell` module and requires an explicit shell
kind, for example `ShellKind.posixSh` or `ShellKind.windowsCmd`. There is no
portable native shell grammar.

The POSIX helper executes `/bin/sh`, `-c`, and the command text as distinct
arguments through the direct process API. Its name and docs warn against
concatenating untrusted input. `ENOEXEC` and PATH search never fall back to this
helper automatically.

Shell helpers are convenience work after direct spawn, communication, and
pipelines are complete. They are not part of the low-level foundation.

## Detached execution

Do not implement the archive's detached API in the first pass. Closing a
waitable POSIX child's local handle does not detach it; it creates a zombie
obligation. A correct POSIX detached operation requires establishing the
lifetime during launch (normally through a tightly audited double-fork helper
or a separate supervisor) and has different error-reporting guarantees from
ordinary spawn. A Windows implementation has different handle/job semantics.

When justified, expose a dedicated `launchDetached` operation with no
`ChildProcess` result. Its documentation must state exactly when exec failure
is known, whether a final PID is informational only, which stdio routes are
allowed, and how session/process-group state is established. Never offer
best-effort rollback by signaling naked recorded PIDs after ownership has been
discarded.

## Native escape hatches

Portable APIs expose an opaque `ProcessId` only for logging and comparison.
They do not accept arbitrary process IDs for termination. Owned signaling uses
the stable child owner so a stale identifier cannot target an unrelated
process.

`xtb.os.process_native` may provide versioned POSIX descriptor/PID access and
Windows HANDLE access. Adoption transfers ownership only after validation and
atomic close-on-exec/non-inheritable configuration succeeds. Release is
available for pipe endpoints because the caller can assume the close
obligation; it is not available for a live child reap obligation.

Arbitrary POSIX signals and extra descriptor mappings belong in this explicit
module. The portable module exposes only cooperative termination and forceful
kill.

## Scratch and allocation

Every operation that converts strings, constructs `argv`/environment blocks,
or creates temporary pipeline stages acquires a `ScratchScope` internally.
Fixed-buffer child communication uses a fixed native poll set on its own stack
and does not require scratch. There are no public `spawnScratchSize`,
`runScratchSize`, or `scope u8[] scratch` parameters.

The dependency is operation-specific rather than package-global. Creating,
closing, reading, or writing a pipe, waiting or signaling, and fixed-buffer
communication do not require scratch. Spawn, portable multi-endpoint polling,
run, and pipeline construction require an installed thread context.

The calling thread must have installed `ThreadContextScope`. Missing context,
no non-conflicting arena, or failure to grow a scratch arena is a panic under
the established scratch contract; these conditions are not part of the
process API's recoverable result.

Scratch conflicts are mandatory when persistent process output is allocated
during the scope:

- `spawn` uses zero conflicts because no D allocation escapes the call;
- fixed-buffer `communicate` does not acquire scratch;
- `run` acquires scratch with its output allocator as a conflict;
- an owning pipeline uses its storage/output allocator as a conflict; and
- an operation writing into pre-existing owners lists every distinct allocator
  whose live storage must survive rewind.

Scratch-backed native strings and pointer arrays remain valid through the
native spawn call and are rewound immediately afterward. Native APIs must not
retain those pointers. Scratch never owns a file descriptor, process handle,
or object requiring a destructor because arena rewind does not run cleanup.

Persistent allocation failure remains recoverable. For example, failure to
grow `RunOutput.stdout` returns `resourceExhausted`, kills/reaps the child,
destroys partial output, and leaves the destination empty. Scratch allocation
failure panics because it is infrastructure failure by deliberate project
policy.

## Linux backend

The normal Linux backend uses `posix_spawn`/`posix_spawnp`-class primitives,
not a general `fork` child path. All string/environment construction and
validation happens in the parent. Spawn file actions perform only native
descriptor mapping, null-device opening, working-directory change, and strict
descriptor closure.

Linux requirements:

- create pipes with `pipe2(O_CLOEXEC)`, then set `O_NONBLOCK` only on an end
  whose requested mode requires it;
- duplicate owners with `F_DUPFD_CLOEXEC` or `dup3(..., O_CLOEXEC)`;
- use ordered spawn actions to map selected handles onto descriptors 0/1/2;
- close every descriptor above stderr in the child with
  `posix_spawn_file_actions_addclosefrom_np` when the configured libc supports
  it;
- use `posix_spawn_file_actions_addchdir_np` for working-directory support;
- never temporarily change the parent's current directory or environment;
- use the error value returned by `posix_spawn` rather than assuming `errno`;
- keep the Linux wait-status encoding in one named, tested backend helper when
  the BetterC bindings expose libc macros as unavailable runtime symbols; and
- use pidfds for readiness when available at runtime, with a tested
  targeted-`waitpid` fallback for older kernels.

Strict child descriptor inheritance is a security property. If the backend
cannot close unknown descriptors race-free, default spawn returns
`unsupported` rather than silently leaking them. A separately and explicitly
named compatibility policy may opt into inheriting non-CLOEXEC foreign
descriptors, but it must never be the default.

Linux's `close` behavior is backend-specific: issue close once, reset the owner
before the call, and never retry after `EINTR`, because a retry can close a
descriptor already reused by another thread. Explicit close may report the
captured error for diagnostics; generic `deinit` intentionally discards it.

The backend may define one central build version that disables native process
support and selects the unsupported stub. Do not scatter feature versions
through public policy code. Any opt-in `fork` fallback must be a separately
reviewed future feature with an enumerated async-signal-safe child operation
list; it is not an automatic fallback for missing libc spawn extensions.

## Windows backend contract

The future Windows backend must use `CreateProcessW` with:

- a non-null explicit application path;
- validated UTF-8 to UTF-16 conversion in scratch;
- a mutable, correctly quoted UTF-16 command-line buffer;
- `STARTUPINFOEX` and `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` so only selected
  handles are inherited;
- native handles made non-inheritable by default;
- an explicit Unicode environment block; and
- a process HANDLE retained for waiting instead of treating the PID as an
  owner.

Deadlock-free communication requires overlapped I/O. Do not substitute ordinary
synchronous anonymous pipes and then claim the same timeout/communication
contract. Use a tested named-pipe/overlapped construction or return
`unsupported` for the affected operation until it exists.

`ProcessIsolation.isolatedTree` maps to a Job object configured for tree
termination. The implementation must account for an application already
running inside a Job and must report unsupported/permission errors rather than
silently degrading to direct-child termination.

## Thread safety and global process state

Distinct owners can be used by distinct threads. Concurrent operations on the
same `ChildProcess`, pipe endpoint, `Pipeline`, capture, or output owner are a
data race unless the application serializes them. Passing an owner to another
thread transfers the responsibility for its scratch context and cleanup.

The implementation must not install signal handlers, change signal
dispositions, change the process working directory, replace `environ`, or
change global stdio. Per-thread temporary SIGPIPE masking is the narrow
exception needed for a safe pipe write and must restore prior state.

The application must serialize conflicting operations on global environment
and SIGCHLD policy. A SIGCHLD handler may observe notification, but it must not
reap PIDs owned by this library. These constraints belong in public docs and
tests, not only backend comments.

## Representative usage

### One-shot capture

```d
ThreadContextScope thread = ThreadContextScope.acquire();

String[2] arguments = ["--format", "short"];
Command command = Command.search("tool", arguments[]);

RunOptions options = RunOptions.capture()
    .withTimeout(milliseconds(2_000));

RunOutput output;
ProcessError error = run(
    command,
    null,
    options,
    mallocAllocator(),
    &output,
);
if (error.failed)
    return 1;
if (!output.exitStatus.succeeded)
    return 2;
```

### Managed streaming

```d
SpawnOptions options = SpawnOptions.init
    .withStdin(InputRoute.piped())
    .withStdout(OutputRoute.piped())
    .withStderr(ErrorRoute.piped());

ChildProcess child;
ProcessError error = spawn(command, options, &child);
if (error.failed)
    return 1;

// The caller may integrate child.stdinPipe/stdoutPipe/stderrPipe with its own
// event loop, or use communicate for the standard pump.
```

### Linear pipeline without a builder

```d
String[1] grepArguments = ["needle"];
String[1] sortArguments = ["-u"];
Command[2] commands = [
    Command.search("grep", grepArguments[]),
    Command.search("sort", sortArguments[]),
];

PipelineOutput output;
ProcessError error = runPipeline(
    commands[],
    null,
    PipelineRunOptions.capture(),
    mallocAllocator(),
    &output,
);
```

The final implementation should preserve this level of call-site simplicity.
It should not force callers to prepare native pointer arrays, calculate scratch
bytes, maintain parallel process-state arrays, or conditionally move stdio
owners.

## Verification plan

Create a dedicated BetterC helper executable under `tests/support/` instead of
depending on shell syntax or the host versions of `echo`, `cat`, and `sleep`.
It should support modes for:

- echoing argv and selected environment values without ambiguity;
- copying stdin to stdout;
- concurrently filling stdout and stderr beyond native pipe capacity;
- emitting arbitrary bytes including NUL and invalid UTF-8;
- exiting with a selected code;
- terminating itself by signal where supported;
- sleeping until a deadline;
- closing stdin early;
- spawning a descendant that inherits or closes selected handles; and
- reporting which test sentinel handles it inherited.

Tests must cover at least:

1. exact and PATH lookup, empty arguments, empty argument strings, spaces,
   quotes, separators, custom `argv[0]`, NUL rejection, and exec failure;
2. inherit/replace/overlay environments, empty values, removal, duplicate
   names, effective PATH, and concurrent-environment contract documentation;
3. working directory and unsupported-backend behavior;
4. every stdio route, stderr merge, borrowed-owner preservation on success and
   failure, and no unintended inherited sentinel descriptor;
5. pipe EOF, would-block, partial I/O, duplicate semantics, peer closure,
   SIGPIPE protection, repeated close, move, and explicit `deinit` cleanup;
6. exit zero/nonzero, signal exit, immediate/finite/infinite waits, EINTR,
   monotonic-clock failure injection, and a timeout that signals cannot extend;
7. simultaneous large stdin/stdout/stderr communication without deadlock;
8. capture at zero, exact capacity, one byte over, continued drain after
   truncation, merged streams, and binary output;
9. leave-running resume, cooperative timeout escalation, forceful timeout,
   direct-child versus isolated-tree behavior, and no remaining zombie;
10. allocator failure at every persistent allocation point with balanced
    cleanup and unchanged/empty outputs;
11. missing thread context and scratch conflict exhaustion through the death
    test mechanism, plus successful scratch reuse;
12. pipeline one/many stages, stage-order statuses, last/every-stage success,
    per-stage stderr, early/middle/late spawn failure, intermediate EOF, and
    cleanup of every previously started stage;
13. checked rejection of `deinit` on unresolved live child/pipeline owners,
    plus explicit kill/terminate-and-wait paths proving descendants are terminated
    and direct children reaped;
14. compile-time rejection of copying each owner and BetterC compilation of
    all public examples; and
15. a pthread stress test that creates pipes and spawns concurrently while a
    child verifies that no unrelated descriptors leaked across exec.

Use fault-injection seams for native calls rather than trying to provoke every
rare kernel error nondeterministically. Run focused tests in normal debug,
optimized, release, ASan, and supported cross-build modes. Native runtime tests
are versioned by backend; unsupported targets still compile the public API and
exercise deterministic `unsupported` results.

## Implementation order

1. Extend shared OS error classification and implement explicit-lifetime pipes with atomic
   inheritance safety.
2. Implement command/environment validation and the Linux spawn backend using
   internal scratch.
3. Implement explicit child wait/termination plus mechanical cleanup and pidfd-assisted waiting.
4. Implement fixed-buffer communicate, then owning `run` on top of it.
5. Implement owning linear pipelines and their communication pump.
6. Add native escape hatches only after the portable invariants are tested.
7. Consider explicit shell helpers; defer detached execution until its launch
   and error contract has a separately reviewed design.

Each step adds its module to the explicit OS test runner and adds a runnable
example before proceeding upward.

## Research basis

The platform decisions above are based on primary platform documentation:

- [POSIX `posix_spawn`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/posix_spawn.html)
  defines argv/environment and ordered file-action semantics without exposing
  arbitrary child-side code.
- [POSIX `wait`/`waitpid`](https://pubs.opengroup.org/onlinepubs/009696899/functions/wait.html)
  defines reap behavior and the incompatible `SIGCHLD` ignored/
  `SA_NOCLDWAIT` cases.
- [Linux `pipe2`](https://man7.org/linux/man-pages/man2/pipe2.2.html) and the
  [`O_CLOEXEC` discussion](https://man7.org/linux/man-pages/man2/open.2.html)
  document atomic close-on-exec creation and the multithreaded leak race in a
  later `fcntl` call.
- glibc added
  [`posix_spawn_file_actions_addchdir_np` in 2.29](https://sourceware.org/pipermail/glibc-cvs/2018q4/066062.html)
  and
  [`posix_spawn_file_actions_addclosefrom_np` in 2.34](https://sourceware.org/pipermail/glibc-cvs/2021q3/073654.html).
- [Linux `close`](https://man7.org/linux/man-pages/man2/close.2.html) explains
  why retrying close can target a reused descriptor.
- [Linux pidfds](https://man7.org/linux/man-pages/man2/pidfd_open.2.html) and
  [`pidfd_send_signal`](https://man7.org/linux/man-pages/man2/pidfd_send_signal.2.html)
  provide pollable, stable process references where available.
- [Microsoft `CreateProcessW`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)
  documents explicit application names, mutable command lines,
  `STARTUPINFOEX`, and handle whitelisting.
- [Microsoft Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
  define process-tree ownership and kill-on-close behavior on Windows.
- The [D struct specification](https://dlang.org/spec/struct.html) governs
  disabled copying, moves, and destructor behavior for the owning value types.
