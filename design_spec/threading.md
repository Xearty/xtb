# Threading library design specification

## Status and scope

This document is the implementation contract for the XTB threading library.
The library is a separate foundational package, `xtb_threading`, alongside
`xtb_core` and `xtb_os`.

The dependency direction is:

```text
xtb_core
├── xtb_threading
└── xtb_os
```

`xtb_threading` depends on `xtb_core`. It must not depend on `xtb_os` merely
because its backends call operating-system APIs. `xtb_os` may later depend on
`xtb_threading` if an OS facility needs synchronization internally, so a
threading-to-OS dependency would create the wrong layering and risk cycles.

The first native backend targets Linux. Windows is part of the architecture and
must use the same public contracts when implemented. Unsupported platforms must
still compile and report an explicit unsupported start error instead of failing
at import time.

The entire library must remain compatible with `-betterC`. It must not require
the GC, exceptions, classes, `TypeInfo`, runtime reflection, module
constructors, or hidden process-wide mutable state.

The threading surface has three deliberate ownership/typing layers plus one
structured-concurrency surface:

1. `Thread.startRaw` exposes a non-template `void*` context API.
2. `Thread.start!function_(args...)` adds type-safe arguments without hidden
   allocation.
3. `spawn!function_(allocator, args...)` represents a typed concurrent
   computation and returns a `JoinHandle!T` whose `join` produces the worker's
   return value.
4. `threadScope(allocator, body)` owns a lexical set of child threads, permits
   scoped borrowing that ordinary `Thread.start` rejects, and joins every
   successfully started child before the scope returns.

The raw API is the backend-facing foundation and remains directly usable.
Typed `Thread.start` and `spawn` build on the raw layer. `threadScope` is a
parallel structured-concurrency adapter over the same raw/thread machinery; it
is not required to route through ordinary typed `Thread.start`, because scoped
workers intentionally permit borrowing forms that ordinary starts reject.

## How to read this specification

This file is intentionally more prescriptive than an API sketch. A later
implementer should treat the words **must**, **must not**, **should**, and **may**
as follows:

- **must / must not**: required for conformance with this design;
- **should**: the expected v1 implementation unless a concrete compiler or
  platform limitation is discovered and documented in the implementation;
- **may**: an implementation choice that does not change the public contract;
- **conceptually**: the names, ownership, failure, and synchronization semantics
  are normative, while the exact D template spelling may be adjusted to make the
  code compile cleanly under the supported LDC version; and
- **prototype gate**: do not freeze the affected public API until the named
  compiler/lifetime experiment has been performed.

When a code block is introduced as the "public API", names and behavior are
intended to be public unless the surrounding text explicitly calls the block
conceptual. Do not add convenience overloads, implicit allocation, implicit
conversion, or additional failure modes merely because they are easy to add.

### Supported and unsupported platforms

"Unsupported platforms must compile" means that importing `xtb.threading` and
building code that does not execute an unsupported OS-dependent operation must
remain possible. It does **not** promise functional blocking/thread creation on a
platform for which no backend exists.

For a backend that is not implemented in v1:

- operations whose API already returns `Result`, such as `Thread.startRaw` and
  thread naming, return their `unsupported` error;
- `hardwareConcurrency()` returns `0` when no truthful hint is available;
- `cpuRelax()` may use a compiler/architecture no-op hint fallback but must not
  turn into a scheduler yield;
- non-blocking atomics may remain available when the compiler target supports
  them; and
- an operation that fundamentally requires the missing parking/thread backend
  and has an infallible public signature must fail through an explicit
  unsupported-platform panic rather than silently spin forever or pretend to
  provide blocking semantics.

The production test matrix distinguishes **compile portability** from **runtime
backend support**. Linux is the first backend on which all runtime semantics are
required.

### Address stability of synchronization objects

Wait/wake primitives identify objects by memory address. Therefore `Atomic!T`
when waited upon, `Mutex`, `CondVar`, `Semaphore`, `Latch`,
`WaitGroup`, `Barrier`, `RwLock`, `Once`, and `OnceCell!T` must be treated as
address-stable after they have been published to another thread or after any
thread could be waiting on them.

These objects should be non-copyable. A bitwise/destructive move before first
publication is acceptable if D requires it for ordinary local construction, but
moving/relocating one while another thread can access it is a programming error.
Containers that relocate elements must therefore not contain live published
synchronization primitives by value unless the container itself guarantees a
stable address.

Most of these primitives own no heap/native handle and therefore need no
platform destruction routine. Their destruction requirement is **quiescence**:
no thread may still own, wait on, or access the object. Checked destructors may
validate obvious non-quiescent state (for example a locked mutex) when this can
be done without adding release metadata; inability to diagnose every waiter does
not weaken the caller's lifetime obligation. `Thread` and `JoinHandle` are different: they are owning handles
specifically designed to be movable between threads.

## Goals

The library must provide:

- raw thread creation with an explicit `void*` context;
- type-safe thread entry functions with compile-time checked arguments;
- typed spawned computations with arbitrary movable return values;
- structured thread scopes with guaranteed join-all semantics and explicit allocator-backed child tracking;
- explicit allocation for APIs that require stable heap storage;
- process-fatal panic semantics that remain consistent across threads;
- a C/C++-style atomic memory model;
- low-level processor relaxation and adaptive polling helpers (`cpuRelax` and `SpinWait`);
- mutexes, condition variables, semaphores, latches, wait groups, barriers,
  read/write locks, one-time initialization primitives, and `OnceCell!T`;
- a narrow internal parking abstraction used to implement blocking primitives;
- all ordinary synchronization primitives (`Mutex`, `CondVar`,
  `Semaphore`, `Latch`, `WaitGroup`, `Barrier`, `RwLock`, `Once`, and
  `OnceCell!T`) are allocation-free; only APIs that explicitly accept an
  allocator (`Thread.startRawAlloc`, `Thread.startAlloc`, `spawn`, and
  `threadScope`) allocate XTB bookkeeping/state;
- zero-valid-state synchronization primitives where the platform-independent
  representation permits it;
- explicit ownership and join/detach obligations;
- thread identity, naming, scheduler-yield, CPU-concurrency, and processor-relaxation utilities; and
- small platform backends hidden behind portable public types.

The following properties are mandatory:

- `Thread.startRaw` performs no XTB allocation;
- typed `Thread.start` performs no hidden allocation;
- `Thread.startRawAlloc` and typed `Thread.startAlloc` allocate exactly through
  the caller-supplied `Allocator*` and use that stable start state to avoid a
  child-start capture rendezvous;
- `spawn` allocates only through the `Allocator*` supplied by the caller;
- `threadScope` allocates and deallocates child-tracking nodes through the same
  caller-supplied allocator, on the scope-owning thread;
- worker arguments are never left borrowing the stack frame of `Thread.start`;
- `JoinHandle!T` never silently detaches;
- ordinary `Thread`/`JoinHandle` destruction never silently blocks waiting for a worker;
- `threadScope` is the explicit exception: its lexical boundary guarantees join-all before returning;
- a panic in any worker thread terminates the process;
- recoverable worker failure is represented by the worker's own return type,
  normally `Result!(T, E)` when appropriate;
- failure to create a native thread is separate from worker failure;
- synchronization precondition violations are programming errors rather than
  routine `Result` values; and
- a successful `join` establishes the synchronization needed to read all state
  published by the completed worker.

## Non-goals for the first implementation

- Futures, promises, general task executors, or work stealing. A thread pool is
  explicitly planned as a higher-level facility, but its queueing, shutdown,
  allocator, task-result, and work-stealing policies are not specified here.
- Async I/O or coroutine scheduling.
- Fibers or user-space context switching.
- Recovering from or catching `panic` at a thread boundary.
- Exception transport between threads.
- Implicit allocation in `Thread.start`.
- Detached `JoinHandle` computations.
- Arbitrary typed return values from the low-level `Thread` abstraction.
- Automatic installation of an XTB `ThreadContext` in newly created threads.
- Automatic affinity, priority, or scheduling-policy management in the first
  implementation. Thread naming is intentionally included and is not part of
  this exclusion.
- Forced thread cancellation, termination, suspension, or resumption. There is
  no `Thread.kill`, `Thread.cancel`, `Thread.suspend`, or equivalent asynchronous
  interruption API.
- Public `SpinMutex` in the first implementation. The normal `Mutex` may spin
  briefly internally before parking.
- Manual-reset/auto-reset Event primitives in the first implementation.
- Multi-mutex deadlock-avoidance helpers such as a `std::lock` equivalent.
- Defining portable semantics for `fork` after multiple threads exist. POSIX
  fork-after-threading behavior is outside the first implementation contract.

Higher-level concurrency facilities, including the planned thread pool, may
later live in `xtb.concurrent` or another dedicated higher-level package built
on `xtb_threading`. The exact package boundary is intentionally deferred until
the pool API is designed.

## Module organization

Use focused public modules and private/package backend modules:

```text
source/xtb/threading/
├── package.d
├── atomic.d
├── thread.d
├── spin_wait.d
├── spawn.d
├── thread_scope.d
├── mutex.d
├── cond_var.d
├── semaphore.d
├── latch.d
├── wait_group.d
├── barrier.d
├── rwlock.d
├── once.d
├── once_cell.d
└── internal/
    ├── parking.d
    ├── countdown.d
    ├── generation_wait.d
    ├── thread_backend.d
    ├── thread_linux.d
    ├── thread_windows.d
    └── thread_unsupported.d
```

`thread.d` owns `Thread`, `ThreadId`, `ThreadStartError`, raw creation, the
typed-argument adapter, thread naming, `hardwareConcurrency`, and scheduler
yield utilities. `spin_wait.d` owns `cpuRelax` and `SpinWait`. `spawn.d` owns
`JoinHandle!T`, `SpawnError`, and typed result transport. `thread_scope.d` owns
`ThreadScope` and the structured `threadScope` entry point.

`atomic.d` is public because atomics are part of the concurrency model even
though their implementation is primarily compiler/CPU functionality rather
than OS functionality. `once_cell.d` builds typed one-time value initialization
on the `Once` machinery without requiring allocation.

Do not create placeholder modules with no coherent implementation. Add each
module when the first complete primitive belonging to it is implemented.

`xtb.threading.package` should publicly re-export the completed public modules so
`import xtb.threading;` exposes the supported foundational surface. It must not
re-export `internal.*` modules or native backend declarations. The DUB target or
subpackage name is `xtb_threading`; D module names remain under
`xtb.threading.*`.

## Common API conventions

Production modules establish truthful common attributes at module or aggregate
scope instead of repeating `nothrow @nogc` on every declaration. Native API
calls and pointer manipulation remain in small `@system` regions. Templates
should infer safety where practical rather than globally forcing `@system` on
otherwise safe typed calls.

Owning thread and join-handle types are non-copyable. Moving them transfers the
join obligation and leaves the source empty.

`Thread` and `JoinHandle!T` should also be marked `@mustuse` if the supported D
attribute applies cleanly to these structs. This is compile-time assistance, not
a replacement for the unconditional runtime ownership checks: intentionally or
accidentally discarding an owning temporary must still not leak/detach it.

Required pointer parameters panic when null according to the normal XTB pointer
contract. A default-initialized owner is empty and valid.

Ordinary recoverable failures use `Result`. Programmer errors such as joining a
thread twice, joining the current thread, or destroying a live join handle are
not routine errors and must not pollute the public API with values callers are
expected to ignore.

The library does not automatically acquire `ThreadContextScope` for a worker.
A newly created native thread begins without an installed XTB thread context.
Code requiring scratch arenas, thread-local logging state, or another facility
owned by `ThreadContext` must explicitly install one in that worker or use a
higher-level wrapper introduced in the future. This keeps low-level creation
free of hidden allocation and policy.

### Manual object lifetime in raw storage

`spawn`, `threadScope`, and `OnceCell!T` use allocator/raw-storage regions where
D cannot automatically know which objects are currently live. Every such region
must have a written live-state invariant and must construct/end each object's
lifetime exactly once.

Use the project's established move/destruction helpers (`core.lifetime.move` or
the XTB equivalent) rather than ad-hoc byte copies for owning/non-copyable
values. "Move a value out and mark the slot inactive" means the source object's
lifetime is ended correctly: if the chosen move primitive leaves a valid
moved-from object that still requires destruction, destroy that moved-from object
before declaring the slot inactive. Do not skip a destructor merely because the
resources were transferred, and do not call a destructor on a raw slot that was
never successfully constructed.

A process-fatal `panic` does not need transactional cleanup because the process
terminates, but ordinary recoverable failure paths (allocation/native-start
failure) must still have exact destruction counts.

### Programming-error enforcement

The design uses two different kinds of programming-error checks; the
implementation must not confuse them:

1. **Required lifecycle/safety checks** remain active in every build when the
   library cannot safely continue without them. Examples include joining an
   empty/already-consumed `Thread`, self-joining, overwriting a live owning
   `Thread`/`JoinHandle`, and destroying an unconsumed `Thread` or
   `JoinHandle`. These terminate through the real panic/fatal path even in
   `release-fast`.
2. **Checked diagnostics** exist to turn otherwise-invalid synchronization use
   into useful diagnostics but may disappear with `XTB_Checked`. Mutex owner
   tracking and recursive-lock detection are the main examples. Code that
   relies on such invalid use has no valid release-mode semantics merely because
   the diagnostic disappeared.

Do not compile away a check if doing so would make a valid owning object leak a
native resource or cause the library itself to access an invalid native handle.
Conversely, do not retain large debug-only ownership metadata in release builds
merely to diagnose caller misuse.

State-integrity checks that prevent arithmetic wrap/corruption are required in
all builds when the invalid operation can be detected without debug-only owner
metadata. Examples include latch/wait-group count underflow and semaphore permit
overflow. Do not turn an invalid decrement into unsigned wraparound merely
because `XTB_Checked` is disabled.

### Move assignment of owning handles

`Thread` and `JoinHandle!T` are move-only. Move construction transfers the
entire ownership obligation and leaves the source in its valid empty state.
Move assignment is only valid when the destination is already empty. Assigning
over a live/joinable destination would silently lose an obligation and must
therefore terminate as a programming error in every build. Do not implement
these types with a generated assignment operator that can overwrite a live
native handle/state pointer.

## Layer 1: raw `Thread`

### Raw entry point

The portable raw entry type is:

```d
alias RawThreadFn = int function(void* context) nothrow @nogc;
```

This is XTB's portable callback contract, not the native OS callback ABI. Each
backend provides the required native trampoline. POSIX may internally require a
`void*`-returning C callback and Windows may require another signature; those
details never appear in the public API.

### Public API

The foundational thread surface is:

```d
struct Thread
{
    @disable this(this);

    static Result!(Thread, ThreadStartError) startRaw(
        RawThreadFn function_,
        void* context = null,
    );

    static Result!(Thread, ThreadStartError) startRawWith(
        ThreadStartOptions options,
        RawThreadFn function_,
        void* context = null,
    );

    static Result!(Thread, ThreadStartAllocError) startRawAlloc(
        Allocator* allocator,
        RawThreadFn function_,
        void* context = null,
    );

    static Result!(Thread, ThreadStartAllocError) startRawAllocWith(
        ThreadStartOptions options,
        Allocator* allocator,
        RawThreadFn function_,
        void* context = null,
    );

    bool joinable() const;
    ThreadId id() const;
    Result!(void, ThreadNameError) setName(String name);

    int join();
    void detach();
}

ThreadId currentThreadId();
void yieldThread();
uint hardwareConcurrency();

Result!(void, ThreadNameError) setCurrentThreadName(String name);
```

`startRaw` is intentionally named `Raw`. It makes type erasure visible at the
call site instead of hiding it behind an overload of `start`.

`function_` is required and must not be null; a null raw entry point is a caller
programming error and is rejected before entering the native backend. `context`
is explicitly nullable and is passed through unchanged.

Example:

```d
struct WorkerState
{
    int index;
}

int workerRaw(void* opaque) nothrow @nogc
{
    WorkerState* state = cast(WorkerState*) opaque;
    return state.index;
}

WorkerState state = WorkerState(7);
auto started = Thread.startRaw(&workerRaw, &state);
Thread thread = started.unwrap();
int status = thread.join();
```

The caller owns the raw context. `startRaw` copies only the pointer. The pointed
object must remain alive and correctly synchronized for as long as the worker
can access it.

### Raw adapter storage and start timing

The portable `RawThreadFn` intentionally does not expose the native thread-entry
ABI. A backend such as POSIX may therefore need an adapter containing both the
runtime `RawThreadFn` and the user context pointer. Two explicit policies are
provided:

- `startRaw` / `startRawWith` remain allocation-free. If the backend cannot pass
  the portable callback directly, it may place its adapter on the starting
  thread's stack and wait only until the child has copied every adapter field it
  needs. This child-start handoff is permitted even though the worker itself
  remains asynchronous.
- `startRawAlloc` / `startRawAllocWith` allocate stable adapter state through the
  supplied allocator. They return as soon as native creation succeeds and do
  not wait for the child to be scheduled merely to consume adapter state. The
  child copies the callback/context, releases the allocation, and then invokes
  the user worker.

The allocating form does **not** take ownership of the raw user context or copy
its pointee. Only XTB's native-ABI adapter state is allocated.

### Thread return value

The low-level `Thread` abstraction uses an `int` completion value. It is a
portable XTB thread status, not a native handle-sized return value. Native
backends translate as necessary.

Typed workers returning `void` through `Thread.start` are normalized to status
zero. Workers that need arbitrary typed return values use `spawn` instead.

### Joining and detaching

`join` and `detach` do not return `Result`.

Failures reported by native join/detach APIs correspond to violated lifecycle
preconditions under XTB's abstraction: joining twice, joining a detached or
invalid thread, joining the current thread, or otherwise corrupting the thread
state. These are programming errors. Checked implementations should diagnose
them precisely; an unexpected native failure that cannot be represented as an
ordinary caller-recoverable state is fatal.

`join` waits for completion, consumes the join obligation, releases native join
resources, and returns the worker's integer status.

There is no join timeout or cancellation in v1. If the worker never terminates,
`join()` may block indefinitely. This is expected behavior, not a recoverable
join error.

`detach` consumes the join obligation and releases XTB ownership of the native
join resources while allowing the worker to continue.

After detach there is no XTB handle with which to determine completion. For raw
contexts and pointer/slice/reference-containing typed arguments, the caller must
therefore arrange a lifetime that remains valid for however long the detached
worker may run. By-value owned captures already transferred onto the worker's
stack remain owned by that worker and are not a caller lifetime problem.

Dropping a live `Thread` without first joining or detaching is a programming
error. The implementation must not silently join because destructors must not
hide unbounded blocking. It must not silently detach because that changes
lifecycle semantics. A live owner reaching destruction therefore terminates
through the programming-error path rather than leaking platform resources.

### Exact `Thread` lifecycle state

The public lifecycle has two semantic states:

```text
empty
  ^
  | move-from / successful join / successful detach
  |
joinable
```

A default-initialized or moved-from `Thread` is `empty`. A successful start
produces a `joinable` handle. "Joinable" means **the handle still owns the join
obligation**, not that the worker is currently executing; a worker may already
have exited while its handle remains joinable.

The following rules are normative:

- `joinable()` returns `false` for `.init`, moved-from, joined, and detached
  handles and `true` for every handle that still owns the obligation;
- `join()` and `detach()` consume the handle and leave it empty;
- `join()`/`detach()` on an empty or already-consumed handle is an unconditional
  programming error;
- `join()` on the current represented thread is an unconditional programming
  error rather than an intentional deadlock;
- `id()` requires a non-empty handle; callers that need an identifier after
  consuming the handle must copy the `ThreadId` first;
- moving a handle does not change the represented thread's identity; and
- destruction of a joinable handle is unconditionally fatal in every build.

`Thread.id()` remains valid on a joinable handle even after the worker has
finished but before it has been joined/detached. It reports identity, not
liveness.

The portable integer completion status preserves the worker's D `int` value,
including negative values. Native trampolines must use a bit-preserving
conversion appropriate to their ABI rather than accidentally truncating or
sign-changing the status.

### Start failure

Thread creation genuinely can fail even when the program is correct, for
example because the system cannot create another thread. Creation therefore
returns:

```d
Result!(Thread, ThreadStartError)
```

`ThreadStartError` belongs to `xtb_threading`; it must not require an
`xtb_os` dependency. It preserves a portable category and the native error code
for diagnostics.

The v1 public error shape is:

```d
enum ThreadStartErrorKind : ubyte
{
    unsupported,
    resourceExhausted,
    permissionDenied,
    invalidConfiguration,
    system,
}

struct ThreadStartError
{
    ThreadStartErrorKind kind;
    int nativeCode;
}
```

`invalidConfiguration` is for a runtime options value that cannot be supported
or represented by the selected backend.

`nativeCode` is diagnostic backend data. V1 Linux stores the relevant errno-style
code directly. Callers must branch on `kind`, not on portable numeric meanings
of `nativeCode`; Windows may use a different native-code domain while preserving
the same portable `kind` categories. Compile-time misuse remains a static
error, and impossible library-generated configuration is an internal bug.

Allocator-backed starts have one additional recoverable failure channel: the
explicit start-state allocation can fail before native creation. They therefore
return a separate error that preserves the distinction instead of pretending an
allocator failure came from the operating system:

```d
enum ThreadStartAllocErrorKind : ubyte
{
    allocationFailed,
    threadStartFailed,
}

struct ThreadStartAllocError
{
    ThreadStartAllocErrorKind kind;
    ThreadStartError threadStartError;
}
```

When `kind == allocationFailed`, `threadStartError` is `.init`. When
`kind == threadStartFailed`, `threadStartError` contains the same native failure
that the corresponding non-allocating start would have returned.

## Layer 2: typed `Thread.start`

### Public shape

The common thread-start API is a template over the worker function:

```d
Thread.start!worker(args...)
Thread.startWith!worker(options, args...)
Thread.startAlloc!worker(allocator, args...)
Thread.startAllocWith!worker(options, allocator, args...)
```

Conceptually:

```d
struct Thread
{
    static Result!(Thread, ThreadStartError)
    start(alias function_, Args...)(Args args);

    static Result!(Thread, ThreadStartError)
    startWith(alias function_, Args...)(
        ThreadStartOptions options,
        Args args,
    );

    static Result!(Thread, ThreadStartAllocError)
    startAlloc(alias function_, Args...)(
        Allocator* allocator,
        Args args,
    );

    static Result!(Thread, ThreadStartAllocError)
    startAllocWith(alias function_, Args...)(
        ThreadStartOptions options,
        Allocator* allocator,
        Args args,
    );
}
```

The exact implementation signature may use `auto ref`, forwarding templates,
or parameter introspection to preserve move semantics, but the public contract
is by-value capture. The thread receives its own values, not references to the
caller frame unless the user explicitly passes a pointer.

Example:

```d
int worker(int index, WorkerConfig config) nothrow @nogc
{
    return index + config.bias;
}

auto started = Thread.start!worker(7, move(config));
Thread thread = started.unwrap();
int status = thread.join();
```

### Worker constraints

The worker must be `nothrow @nogc` and must accept the supplied arguments after
normal D initialization/conversion rules allowed by the template contract.
All construction, conversion, move, and destruction performed by the adapter
must itself be valid under `nothrow @nogc`; the typed API must reject a call if
transporting the selected argument types would require throwing or GC-backed
operations.

The v1 typed syntax `Thread.start!worker(...)` accepts an alias to a
context-free module-level/static function symbol. Static member functions are
permitted. Capturing delegates, nested functions with hidden context, alias
parameters that name a local callable object, and other callables whose
invocation requires an implicit context pointer are rejected. A non-static
receiver must be passed explicitly as an argument, normally by pointer when
shared identity is intended.

Do not silently broaden the template to runtime typed function-pointer values in
v1. The raw layer already provides a runtime `RawThreadFn` escape hatch. If a
future use case needs a runtime **typed** function pointer plus typed arguments,
add a separately designed overload whose function pointer is captured as data;
do not make `alias function_` accidentally borrow a local variable that stores a
function pointer.

For the first implementation, worker parameters using `ref`, `out`, or `lazy`
are rejected. Their cross-thread meaning is too easy to misunderstand. The
supported LDC 1.42.0 / DMD 2.112.1 prototype also rejects `in` on typed starts:
without `-preview=in` it currently behaves as a value parameter, while enabling
that preview makes the same spelling alias caller storage. XTB does not let a
build flag silently change a thread-transport lifetime contract. `scope` and
`return` may decorate otherwise-by-value parameters; they do not by themselves
make the captured transport slot alias caller storage. Shared borrowed state is
explicit through pointer-like payloads:

Top-level type qualifiers such as `const` are not themselves borrowing modes.
The adapter may use an unqualified internal transport object when necessary to
perform a legal move and then pass it to the final by-value parameter with the
worker's declared qualifier. This is an implementation detail: all user-visible
conversion into the worker's value type still occurs before native start.

The normative rule is that typed starts support **value parameters** and reject
parameter modes that make the worker parameter an alias to caller storage. The
LDC prototype above is part of the v1 trait policy; if D later gives `in` one
stable non-aliasing meaning across supported build modes, accepting it can be a
separate API-compatible broadening. Top-level `shared`/`inout` worker parameter
qualification is also rejected in the first typed implementation until the
broader qualifier-preservation prototype is complete; pointers/references to
explicitly shared pointees remain a separate shallow-capture case.

```d
void worker(SharedState* state) nothrow @nogc;
Thread.start!worker(&state);
```

The caller then owns the pointed object's lifetime and synchronization.

A typed `Thread.start` worker returns either `int` or `void` **by value**. `void`
maps to status zero. `ref` returns are rejected even when their referred-to type
is `int`; other return types are rejected with a diagnostic directing the caller
to `spawn`.

### Capture types and conversion timing

Argument conversion and capture happen synchronously in the starting thread
before native thread creation. Capture storage is constructed in the worker's
parameter types, not in whatever incidental expression types appeared at the
call site. This makes conversion side effects deterministic and avoids running
implicit conversions for the first time on the child thread.

For example, if the worker accepts `Config` and the caller supplies a type that
converts to `Config`, the `Config` capture is constructed before invoking the
native start operation. If capture construction cannot satisfy `nothrow @nogc`,
the typed overload is rejected at compile time.

For `startAlloc`, ordinary D function-call copying/moving into the start
function's by-value `Args` occurs before its body runs. The explicit state
allocation is then attempted, and conversion from those argument values into the
worker's declared parameter types occurs in the starting thread before native
creation. Therefore an allocation failure may leave an explicitly moved caller
value moved-from, but it does not run worker-parameter conversion side effects.
A native-start failure occurs only after all typed captures have been
constructed and must destroy those captures exactly once before deallocation.

### Argument ownership

Typed argument transport is a shallow value capture, not a deep ownership
operation. A copyable lvalue argument is copied into capture storage. A
move-only value is transferred explicitly:

```d
Thread.start!worker(move(config));
```

Copying a value that contains pointers, slices, delegates, or other borrowed
references copies those references; it does not extend the lifetime of the
referenced storage. For example:

```d
void worker(const(char)[] text) nothrow @nogc;
```

The slice object is captured by value, but its backing characters remain
caller- or otherwise externally-owned. The same rule applies recursively to
structs containing slices or pointers. Users must ensure that borrowed storage
remains alive and correctly synchronized for the entire period in which the
worker may access it.

The call consumes its by-value arguments according to normal D semantics even
if native thread creation later fails. There is no attempt to reconstruct a
moved-from caller value after a failed start.

### Zero-allocation transfer

Typed `Thread.start` must not allocate merely to adapt a typed function to the
raw `void*` interface.

The implementation uses a temporary typed start packet in the starting
thread's stack frame:

```text
starting thread stack
    |
    | StartPacket!(worker, Args...)
    v
Thread.startRaw(trampoline, &packet)
    |
    v
new thread
    |
    | move/copy packet arguments to its own stack
    | publish "captured"
    v
starting thread observes capture
    |
    v
Thread.start returns
```

The parent must not return while the child can still access the packet. The
child therefore captures all typed arguments into its own stack storage and
signals a one-shot internal start latch before invoking the user's worker.

The latch is an internal synchronization primitive built on atomics and the
parking backend. It is not a public condition variable and must not allocate.

The start-packet handshake is a strict ownership transfer, not merely a startup
notification. A suitable reference protocol is:

```text
parent: packet.captureState = pending
parent: startRaw(trampoline, &packet)
child : construct/move every child-local argument from packet
child : perform the final read of every packet field needed by the trampoline
child : store captured with release ordering; notify waiter
parent: wait until captured with acquire ordering
parent: packet may now be destroyed and start() may return
child : invoke user worker using child-local arguments
```

The child must publish `captured` only after it will never dereference the parent
packet again. The worker itself is invoked **after** publication so a long-running
worker cannot keep `Thread.start` blocked. The acquire/release edge is required
to prove that the parent cannot destroy packet storage while the child still
reads it. Spurious wakeups are handled by rechecking the capture state.

If native thread creation fails, no child can access the packet and the typed
arguments are destroyed normally in the starting thread.

This handshake makes typed `Thread.start` slightly more synchronous than
`startRaw`, but the cost is dominated by native thread creation and buys
zero-allocation typed ownership with a simple lifetime proof.

This timing difference is observable and intentional: allocation-free typed
`Thread.start` waits until the child has captured its stack packet. On a backend
whose portable raw callback also needs a stack adapter, `startRaw` may perform a
smaller equivalent ABI handoff first. Neither operation waits for user worker
completion. A successfully created child that is not scheduled promptly can
therefore delay these zero-allocation start calls even though the thread's user
work remains asynchronous.

### Allocator-backed typed start without a capture rendezvous

`startAlloc` and `startAllocWith` offer the other explicit policy. They allocate
one stable typed start state through the supplied `Allocator*`, construct the
worker-parameter captures in that storage on the starting thread, and pass the
stable state directly to a native backend trampoline. Successful native creation
can therefore return without waiting for the child to run.

Conceptually:

```text
starting thread
    |
    | allocate StartAllocState!(worker, Params...)
    | construct typed captures
    v
native create(stable state)
    |
    +----------------------------> startAlloc returns Thread
                                     without child-start rendezvous

child thread
    | move every typed capture to child-local call storage
    | destroy/mark source captures inactive
    | release start-state allocation through supplied allocator
    v
invoke user worker
```

The start allocation is temporary transport storage only; it does not survive
until `join` and does not store a typed result. The child must release it **before**
entering user worker code once all callback/capture values needed by the worker
are child-local. This keeps long-running workers from pinning temporary start
storage.

Successful native creation transfers ownership of the start allocation to the
child. Native-start failure leaves ownership with the starting thread, which
destroys all constructed captures and deallocates the state before returning
`threadStartFailed`. Allocation failure returns `allocationFailed` and starts no
native thread.

The allocator contract is intentionally stronger than for the zero-allocation
form:

- the `Allocator*` object and any state it references must remain valid until the
  child releases the start allocation;
- deallocation may occur on the newly created child thread, so the allocator must
  permit that cross-thread deallocation; and
- arena/scratch/thread-affine allocators are unsuitable unless their own
  lifetime and cross-thread rules explicitly satisfy both requirements. Resetting
  or popping an arena before the child has consumed the packet is invalid.

There is deliberately no handle method exposing "start packet consumed". A
successful `join` is always late enough to end the allocator lifetime, but it is
not necessary to retain the allocator for the entire worker if the application
has some other valid lifetime guarantee. After `detach`, the caller must keep
the allocator valid until it can independently guarantee that the child has
consumed/released the start state. Long-lived process allocators such as XTB's
malloc allocator naturally satisfy this use case.

The callable restrictions, parameter-mode restrictions, shallow-reference rules,
`int`/`void` return contract, and conversion-before-native-start semantics are the
same as ordinary typed `Thread.start`. The difference is only the explicit
allocation/lifetime policy and the absence of the child-start rendezvous.

## Layer 3: `spawn` and `JoinHandle!T`

### Meaning of `spawn`

`Thread.start` creates an execution resource. `spawn` creates a typed concurrent
computation.

Given:

```d
T worker(Args...) nothrow @nogc;
```

`spawn!worker(...)` returns a handle whose `join` returns exactly `T`.

Example:

```d
int compute(int left, int right) nothrow @nogc
{
    return left + right;
}

auto started = spawn!compute(allocator, 20, 22);
auto handle = started.unwrap();

// Work concurrently here.

int answer = handle.join();
```

For a `void` worker:

```d
void worker(Job job) nothrow @nogc;

auto handle = spawn!worker(allocator, move(job)).unwrap();
handle.join();
```

### Why `JoinHandle` is separate from `Thread`

`Thread` represents lifecycle and an integer completion status. A
`JoinHandle!T` additionally owns stable storage into which a worker can publish
an arbitrary typed value after `spawn` has returned.

Making `Thread` itself generic would unnecessarily mix thread identity with
result transport. Keeping the types separate preserves the layering:

```text
Thread.startRaw(void*)
        ↑
Thread.start!worker(typed arguments)
        ↑
spawn!worker(...) -> JoinHandle!T
```

### Public shape

The intended API is:

```d
struct JoinHandle(T)
{
    @disable this(this);

    bool joinable() const;

    static if (is(T == void))
        void join();
    else
        T join();
}
```

`JoinHandle` deliberately has no `detach` operation.

The spawn functions are conceptually:

```d
Result!(JoinHandle!(ReturnType!function_), SpawnError)
spawn(alias function_, Args...)(
    Allocator* allocator,
    Args args,
);

Result!(JoinHandle!(ReturnType!function_), SpawnError)
spawnWith(alias function_, Args...)(
    ThreadStartOptions options,
    Allocator* allocator,
    Args args,
);
```

`spawn` uses default `ThreadStartOptions`; `spawnWith` applies the same portable
native-thread options as `Thread.startWith`. The allocator remains explicit in
both forms.

The exact template implementation may use compiler traits to derive the return
and capture types. Spawned workers follow the same callable restrictions and
shallow-capture rules as typed `Thread.start`. A spawned return type must be an
ownable value type (or `void`); `ref` returns and other borrowed return forms are
rejected.

Result transport is also shallow. A returned pointer, slice, or aggregate
containing references is copied/moved as a value; `spawn` cannot prove the
referenced storage outlives the worker. Returning a slice/pointer into the
worker's own stack is therefore a programming error even though the outer return
type is a value. Heap/external/static references with a valid lifetime remain
legal. Reject explicit `ref` returns because those are unambiguously borrowed at
the function boundary. All library-performed construction, move, and destruction involved in
argument/result transport must satisfy `nothrow @nogc`.

### Explicit allocation

Arbitrary typed results must outlive the worker's stack until the joining
thread retrieves them. `spawn` therefore requires stable shared storage.
Allocation is explicit in the API:

```d
spawn!worker(allocator, args...)
```

There is no allocator-free overload that silently falls back to malloc or the
GC.

Calling `spawn` consumes/copies its by-value arguments according to the same
rules as ordinary typed start **before the function can report allocation or
thread-start failure**. In particular, `spawn!worker(allocator, move(value))`
may leave `value` moved-from even when allocating `SpawnState` fails. This is
normal D by-value call semantics; `spawn` does not attempt transactional rollback
of caller values.

The allocator must satisfy the size and alignment requested for the concrete
`SpawnState`. Allocation failure means no state object was constructed and no
native thread was started. After allocation succeeds, every partially
constructed capture has an explicit cleanup path if a later capture construction
or native start cannot complete; under the v1 `nothrow @nogc` transport rules,
ordinary construction cannot return a recoverable error, but panic-safe
process-fatal behavior must still not cause double destruction.

The allocator pointer must remain valid until `JoinHandle.join` releases the
spawn state. `JoinHandle` may be moved to and joined from another thread, so the
allocator supplied to `spawn` must permit deallocation from any thread to which
the handle may legally be transferred. Passing a thread-affine allocator and
then joining from an incompatible thread is a programming error.

A later `spawnInto` API may support caller-provided stable storage and avoid
allocation entirely, but it is not required for the first implementation.

### Spawn state

V1 uses exactly one XTB allocation per successful `spawn` attempt that reaches
state allocation. That single allocation contains the type-erased header,
captured arguments, result storage, allocator identity/metadata, and any state
required by the trampoline. Do not split these pieces into multiple allocator
requests in v1; one allocation keeps failure cleanup, ownership transfer, and
deallocation provenance simple:

```text
SpawnState!(worker, Args...)
├── Allocator* owner
├── captured arguments
├── uninitialized T result storage   # omitted for void
└── small state metadata
```

The returned `JoinHandle` owns:

```text
JoinHandle!T
├── Thread thread
└── SpawnState* state
```

`JoinHandle!T` cannot name the concrete capture type because two workers with the
same return `T` may have completely different argument tuples. The allocation
must therefore begin with a stable type-erased header whose layout depends at
most on `T`, followed by concrete typed capture storage known only to the spawn
trampoline.

The required conceptual layout is:

```text
SpawnStateConcrete!(worker, Captures...)
├── SpawnStateBase!T                 # common prefix / offset zero
│   ├── Allocator* owner
│   ├── allocation size/alignment (or equivalent allocator metadata)
│   ├── raw result storage for T     # omitted for void
│   └── result-live flag/state
└── typed capture storage
```

`JoinHandle!T` stores `SpawnStateBase!T*`, not a pointer whose static type
contains the worker/capture tuple. The concrete child trampoline receives the
full concrete-state pointer. This preserves one allocation while allowing the
handle implementation to be independent of argument types.

To keep join-time cleanup type-erased **without** a hidden virtual interface,
the child trampoline must consume/move each typed capture out of the state and
finish/destroy the source capture storage before invoking the user worker. From
that point until join, no typed capture object remains live in the allocation;
only the common header and eventual `T` are live. Native-start failure happens
before the child can perform this transition, so the templated `spawn`
implementation that still knows the concrete state type destroys captures on
that failure path.

If the existing XTB allocator requires size/alignment or another token to
perform deallocation, store exactly that metadata in the common header. If it
can free solely from the pointer, unnecessary metadata may be omitted. The
semantic requirement is that `JoinHandle!T` can correctly deallocate the exact
original allocation after the worker has completed without knowing the capture
types.

The common header/base itself is a real typed object and must have its known live
fields destroyed before raw deallocation. After `Thread.join()` consumes the
embedded thread and `T` is moved/destroyed as appropriate, destroy the remaining
base/header object exactly once. Only the **capture tail** is guaranteed to have
been made inactive by the child trampoline.

Place the common base at a representation location from which the original
allocation pointer can be recovered safely. If D layout guarantees the first
field at offset zero for the chosen concrete struct, document/assert that; if
not, record the allocation-start pointer explicitly. Do not reconstruct a
container pointer with an undocumented layout assumption.

The state address is stable while the native worker is running.

`spawn` therefore does not need the stack-packet handshake used by typed
`Thread.start`. The worker can capture or directly consume its arguments from
the stable allocation after `spawn` has returned.

Consequently, `spawn`/`spawnWith` may return immediately after successful native
creation and handle construction without waiting for the child to run. The
stable allocation, not a startup handshake, proves argument lifetime.

### Spawn-state lifetime model

The implementation must track which manually managed objects in `SpawnState`
are live. The semantic state machine is:

```text
arguments initialized
    |
    | child moves arguments to child-local storage
    | child destroys/marks inactive every source capture slot
    v
arguments empty (common header can now be cleaned type-erased)
    |
    | worker executes, returns, and result is constructed
    v
result initialized
    |
    | join moves result out
    v
result empty
    |
    | metadata cleanup + deallocation
    v
state dead
```

For a `void` worker, the result states are omitted. Native-start failure occurs
while the arguments are still initialized; cleanup must destroy those argument
objects exactly once before deallocation. After the worker has consumed an
argument, generic state cleanup must not destroy that moved-from slot as though
it still contained a live object. After `join` moves out the result, state
cleanup must likewise not destroy the result a second time.

The concrete implementation may use explicit tags, per-region initialized
flags, or another representation that proves the same invariant. It must never
read or destroy inactive union/raw-storage members.

### Spawn algorithm

Conceptually:

```text
spawn!worker(allocator, args...)
    |
    | allocate SpawnState
    | move/copy arguments into state
    v
Thread.startRaw(spawnTrampoline, state)
    |
    +-- failure -> destroy state, deallocate, return SpawnError
    |
    v
return JoinHandle(thread, state)
```

The worker trampoline does:

```text
move/copy captured arguments into worker call
    |
    v
T result = worker(args...)
    |
    v
move result into stable result storage
    |
    v
return native thread status 0
```

For `void`, there is no result storage and successful return is enough.

`JoinHandle.join` does:

```text
Thread.join()
    |
    | establishes completion synchronization
    v
move T out of result storage
    |
    | destroy remaining spawn state
    | deallocate through supplied allocator
    v
return T
```

This supports non-copyable/move-only return values.

### Spawn failure type

`spawn` can fail before or during native thread creation. Unlike
`Thread.start`, it also performs an allocation. Its error type must therefore
represent both causes instead of pretending every failure is a
`ThreadStartError`.

The v1 public error shape is:

```d
enum SpawnErrorKind : ubyte
{
    allocationFailed,
    threadStartFailed,
}

struct SpawnError
{
    SpawnErrorKind kind;
    ThreadStartError threadStartError;
}
```

When `kind == allocationFailed`, `threadStartError` is `.init`. A tagged-union
representation may be used instead if XTB gains a standard variant facility;
the public semantic distinction is what matters.

This keeps the two failure channels conceptually separate:

```text
spawn failure
    Result!(JoinHandle!(WorkerReturn), SpawnError)

worker failure
    WorkerReturn itself, e.g. Result!(Config, ParseError)
```

If a worker naturally returns `Result!(T, E)`, `JoinHandle.join` returns that
same `Result!(T, E)`. `spawn` must not flatten worker errors into `SpawnError`.

Example:

```d
Result!(Config, ParseError) loadConfig(Path path) nothrow @nogc;

auto spawned = spawn!loadConfig(allocator, path);
JoinHandle!(Result!(Config, ParseError)) handle = spawned.unwrap();
Result!(Config, ParseError) loaded = handle.join();
```

### Exact `JoinHandle` lifecycle

`JoinHandle!T` mirrors the ownership discipline of `Thread`:

```text
empty <----- successful join ----- joinable
  ^                               /
  `----------- move-from --------'
```

A default/moved-from/joined handle is empty. `joinable()` describes the
outstanding join/result obligation and does not report whether the worker is
still executing. `join()` consumes the handle and leaves it empty. Calling
`join()` on an empty/already-consumed handle, joining from the represented
worker, overwriting a live handle by move assignment, or destroying a live
handle is unconditionally fatal in every build.

`JoinHandle.join()` first joins the underlying `Thread`. The internal spawn
trampoline's raw integer status is always zero on normal return; a nonzero status
from that internal trampoline indicates an XTB implementation bug and is fatal,
not a worker-domain result. After the join synchronization edge, `join()` moves
`T` exactly once from stable result storage, marks that storage inactive,
destroys all remaining state, deallocates through the recorded allocator, and
returns the moved value. `JoinHandle!void.join()` performs the same cleanup
without result extraction.

### No detach for `JoinHandle`

A `JoinHandle!T` owns both a running computation and storage for an eventual
`T`. Detaching would require transferring state ownership to the worker,
destroying an unobserved result, and arranging allocator-safe self-cleanup.
That is useful in some systems but it weakens the simple ownership contract.

The first implementation therefore does not provide `JoinHandle.detach`.

Callers wanting fire-and-forget execution use `Thread.start`/`Thread.detach`
instead. Callers using `spawn` are explicitly choosing a computation whose
result must be joined.

Destroying a still-joinable `JoinHandle` is a programming error. The destructor
must not silently join because that hides unbounded blocking, and it cannot
silently detach because detach is not part of the abstraction. A live handle
reaching destruction therefore terminates through the programming-error path.
Joining a `JoinHandle` from the worker represented by that same handle is also a
programming error.

`Thread` and `JoinHandle` are uniquely owned but are not internally synchronized
for concurrent method calls. Either owner may be moved between threads, but
calling operations concurrently on the same handle object is a programming
error unless a future API explicitly documents otherwise.

## Structured concurrency with `threadScope`

`threadScope` is the structured-concurrency surface for child threads that may
borrow from a lexical parent scope. It deliberately differs from ordinary
`Thread.start`: the scope owns every child and guarantees that no successfully
started child remains running when the scope returns normally.

The intended usage is:

```d
int value = 41;

threadScope(allocator, (ref scope) {
    scope.spawn!increment(value).unwrap();
    scope.spawn!doOtherBorrowedWork(...).unwrap();

    // Parent work may run concurrently with the children here.
}); // every successfully started child is joined before returning
```

A scoped worker may use a `ref` parameter because the structured boundary keeps
the worker lifetime inside the lexical lifetime of the borrowed object:

```d
void increment(ref int value) nothrow @nogc
{
    ++value;
}
```

The exact D template/delegate spelling must be prototyped with LDC, `scope`, and
DIP1000 before the API is frozen. The implementation must not claim static
non-escape guarantees that the compiler cannot actually enforce.

Independently of the final spelling, the v1 **semantic** signature is fixed:

- the scope body returns `void`;
- the scope body and all scoped workers are `nothrow @nogc`;
- `threadScope` itself does not return until every successful child has been
  joined and its node deallocated; and
- the `ThreadScope` capability is usable only by the thread executing the scope
  body. It is not a sendable child capability.

Do not add a generic body return value in v1. Returning arbitrary body values
would create another escape surface for references tied to the scope and is not
needed for the intended structured-borrow use case. In particular,
the experiments must verify that the scope body itself does not allocate a GC
closure under `-betterC`, that the `ThreadScope` capability cannot escape the
body, and that borrowed arguments cannot be returned or stored through an
obvious compiler-permitted escape path. If D cannot prove the desired contract
with the pleasant call syntax above, prefer a slightly more explicit structured
API over unsound convenience.

The preferred prototype order is:

1. try the lambda/callback syntax shown above with a `scope`/non-escaping body so
   capturing outer lvalues uses only caller-stack context and no GC closure;
2. if that cannot be expressed soundly, fall back to a context-free body plus an
   explicit caller-owned context pointer/reference, for example conceptually:

   ```d
   void scopeBody(ref ThreadScope scope, Context* context) nothrow @nogc;
   threadScope!scopeBody(allocator, &context);
   ```

   The context object must outlive the full `threadScope` call and becomes the
   explicit source of borrowed state.

Do **not** fall back to allocating a closure, keeping the body context alive past
the lexical call, or weakening `-betterC`/lifetime guarantees simply to preserve
the preferred surface syntax.

Structured lifetime bounds the worker's execution, but it cannot magically make
all code safe: a worker that manually stores a borrowed pointer into global or
longer-lived storage still violates the borrowing contract. Such escapes are a
programming error even if the type system cannot diagnose every case.

### `ThreadScope` child API

`ThreadScope` is a capability created only by `threadScope`; users do not
construct meaningful scopes directly. Its fields/initializing constructor remain
package-private. `ThreadScope.init` is an inert invalid capability, and attempting
to call `spawn` on it is a programming error. This prevents a default-created
scope from pretending to own allocator/lifetime state.

Conceptually, the scope capability provides:

```d
struct ThreadScope
{
    Result!(void, SpawnError)
    spawn(alias function_, Args...)(Args args);

    Result!(void, SpawnError)
    spawnWith(alias function_, Args...)(
        ThreadStartOptions options,
        Args args,
    );
}
```

The first implementation accepts `void` scoped workers. The worker itself follows
the same context-free module/static function-symbol restriction as ordinary
typed `Thread.start`; the relaxation in this layer is about **argument borrowing**,
not hidden callable context. There is no individual join handle and therefore no
result channel whose value could be retrieved. A
worker that needs a typed result uses top-level `spawn`/`JoinHandle!T` instead.
A future structured-result API may be designed separately rather than silently
discarding worker return values.

Unlike ordinary typed `Thread.start`, `scope.spawn` may accept `ref` parameters
whose lifetime is proven/bounded by the enclosing `threadScope`. `out` and
`lazy` remain rejected in v1 because their cross-thread initialization and
evaluation semantics add complexity without a demonstrated need. By-value
arguments retain the same shallow-capture rules as ordinary typed starts.

A scoped `ref` capture is represented as a pointer/reference to the caller's
existing lvalue; it is **not** copied into the child node.

The referent must outlive the **callback frame**, not merely appear textually
inside the callback. In the proposed callback-shaped API, a local variable
declared inside the `threadScope` body is normally destroyed as that callback
returns, before the outer `threadScope` function can perform join-all. Such a
body-local must therefore **not** be borrowed by a child in v1 unless the final
compiler prototype proves a different destruction ordering and explicitly
updates this contract. The intended borrowed values are caller/enclosing-scope
objects whose lifetime extends across the entire `threadScope(...)` call. The argument supplied
for a `ref` parameter must therefore be an addressable lvalue, not a temporary,
and its lifetime must enclose the complete `threadScope` invocation. Qualifiers
on the referenced type (`const`, etc.) are preserved. By-value parameters are
stored as owned capture values in the node and may be moved to child-local
storage before invoking the worker.

The structured lifetime guarantee prevents the worker from outliving the
borrowed object, but it does not prevent data races. While a child has mutable
`ref` access, the parent and sibling threads must not concurrently access the
same object incompatibly unless they synchronize separately. The library does
not treat lexical lifetime as synchronization.

Passing the `ThreadScope` object itself, a pointer to it, or an object that
contains such a pointer into a scoped child is outside the v1 contract. Nested
parallelism is expressed by the child opening its own independent
`threadScope`, not by mutating its parent's child list.

### Explicit allocator-backed tracking

`threadScope` supports an arbitrary runtime number of children by allocating one
stable tracking/capture node per successfully attempted child through the
caller-supplied allocator. There is no hidden fallback allocator and no fixed
compile-time child capacity.

Conceptually:

```text
ThreadScope
├── Allocator* allocator
└── intrusive forward list of ChildNode

ChildNode
├── Thread
├── typed scoped capture state
└── forward-list tracking hook
```

V1 should use XTB core's existing `IntrusiveForwardList` with a
`ForwardListHook` embedded in the common child header. `xtb_threading` already
depends on `xtb_core`, so this does not create a dependency cycle, and it avoids
inventing a second intrusive list implementation merely for scope bookkeeping.

The allocator-backed child allocation is what provides address stability; the
intrusive forward list does **not** create that stability. It takes advantage of
the fact that every successfully started child already needs stable storage until
join-all completes. Embedding the forward-list hook in that same allocation lets
`ThreadScope` register the child without allocating a separate container node.

A doubly linked `IntrusiveList` is unnecessary for v1. `ThreadScope` only needs
to register children and later traverse/drain all of them during join-all. It does
not need arbitrary middle removal, reverse traversal, or O(1) unlinking from an
independently held node. `IntrusiveForwardList` therefore expresses the required
operations with one link per child instead of two. Join order remains an
implementation detail, so insertion at the forward-list front is acceptable.

The common header is the intrusive node type; typed child capture storage is
outside the list's type knowledge. If a concrete D template constraint makes
that impossible, preserve the same one-node/zero-extra-allocation property and
document the deviation.

Children are heterogeneous: different `scope.spawn!worker` instantiations have
different capture tuple sizes/types. The intrusive forward list must therefore link a
common non-template header, not pretend every node has one concrete capture type.
The required conceptual layout is:

```text
ScopedChildNodeConcrete!(worker, Captures...)
├── ScopedChildHeader                 # common prefix / linked by scope
│   ├── Thread thread
│   ├── ForwardListHook!ScopedChildHeader hook
│   └── allocation size/alignment (or equivalent allocator metadata)
└── typed capture storage
```

The concrete scoped trampoline knows the complete node type; `ThreadScope`
tracks only `ScopedChildHeader*`. As with `spawn`, the child must move/consume
and finish/destroy the typed source capture storage before invoking user code.
After `Thread.join()` returns, the owner thread can therefore deallocate the raw
node using the common header's allocator metadata without needing a destructor
function pointer for unknown capture types.

If implementation experiments show that the allocator API or D destruction
rules make a cleanup callback simpler/safer, a `nothrow @nogc` type-erased
`destroyNode` function pointer in the header is an acceptable alternative. Do
not use classes, TypeInfo, GC allocation, or runtime reflection for this type
erasure.

After join-all consumes the header's `Thread`, destroy the known common header
fields before deallocating the raw block. As with spawn state, either make the
header recover the original allocation address by a documented/asserted layout
or store that pointer explicitly.

The same allocator that allocates a child node must deallocate that node. All
tracking-node allocation and deallocation happen on the thread executing
`threadScope`; child workers never free scope bookkeeping. Therefore the
allocator must remain valid for the entire `threadScope` invocation but does not
need cross-thread deallocation support merely because it is used by
`threadScope`. This is intentionally different from top-level `spawn`, where a
`JoinHandle` may be moved and joined on another thread.

`scope.spawn` allocates/constructs the tracking and capture state first, then
starts the native child. If allocation fails it returns a `SpawnError` with kind `allocationFailed`. If
native start fails it destroys the partially constructed node and deallocates it
with the same allocator before returning a `SpawnError` with kind
`threadStartFailed`.

Each successful start immediately becomes owned by the scope. If a later child
start fails, all earlier children remain registered and will still be joined at
the boundary. Handling a start error never leaks or detaches prior children.

### Scoped child-node lifetime

Each node has a small explicit lifecycle analogous to `SpawnState` but without a
result:

```text
node allocated
    -> by-value captures constructed / ref captures recorded
    -> native thread successfully started (scope owns Thread)
    -> child moves any owned value captures to child-local storage
    -> child runs and returns void
    -> scope joins Thread
    -> remaining active capture/tracking fields destroyed
    -> node deallocated by scope-owning thread with original allocator
```

Native-start failure occurs before the node is linked as a live child; destroy
all constructed captures and deallocate immediately. Once start succeeds, link
(or otherwise register) the node with the scope **before returning success to the
body** so there is no interval in which the body believes a child exists but
join-all cannot find it. If linking itself cannot fail, this ordering is simple:
construct node -> start -> link -> return `ok()`.

Because the node is already stable allocated storage, `scope.spawn` does not need
the typed `Thread.start` stack-capture handshake. The child may run before,
during, or after node registration, but the node cannot be freed until scope
join-all and registration is complete before `scope.spawn` reports success.

As with `SpawnState`, owned capture slots that have been moved into child-local
storage must not later be destroyed as though still active. Use an explicit
capture-state flag/tag or a transport representation whose destructor is known
to be valid after move; do not rely on reading inactive raw storage.

### Scope exit and join-all

Automatic joining is intentional here and nowhere else:

```text
ordinary Thread / JoinHandle destruction
    -> never silently blocks

threadScope lexical boundary
    -> explicitly guarantees join-all
```

Because there is no cancellation/timeout facility, that lexical boundary may
block indefinitely if any child never terminates. This is an intentional
structured-concurrency consequence, not hidden destructor behavior: the caller
explicitly entered `threadScope`.

On normal body completion, including an early return from the scope body,
`threadScope` joins every registered child, destroys its capture/tracking state,
and deallocates the node through the original allocator before returning to the
caller.

Every scoped trampoline is a raw `void`-semantic worker and therefore returns
raw thread status zero. Join-all ignores no domain result because scoped workers
are required to return `void`; a nonzero raw status from an internal scoped
trampoline is an XTB implementation invariant failure and is fatal.

The join order is an implementation detail unless a future API gives it
observable semantics.

A panic remains process-fatal, so the library does not need exception-style
unwinding logic to recover and join children after panic. No scoped child may be
detached. The `ThreadScope` capability is not internally synchronized for
concurrent mutation by multiple parent threads; calls to `scope.spawn` are made
through the owning scope thread unless a future API explicitly broadens that
contract.

## Panic semantics

`panic` is process-fatal regardless of which thread invokes it.

A worker panic is not a recoverable `JoinError` and is not represented as a
missing `T` inside `JoinHandle`. BetterC has no exception unwinding mechanism
that could safely catch a panic at the worker boundary while running all normal
cleanup.

The library must not attempt to emulate recoverable thread panics with
`setjmp`/`longjmp`, signals, or equivalent control-flow tricks. Those mechanisms
can skip destructors and violate XTB ownership invariants.

Therefore, if the process remains alive until `JoinHandle.join` returns, the
worker completed normally and produced its declared return value.

The intended distinction is:

```text
programming/invariant failure
    panic(...) -> entire process terminates

expected worker failure
    worker returns Result!(T, E)

spawn infrastructure failure
    spawn returns Result!(JoinHandle!T, SpawnError)
```

This is why `JoinHandle.join` returns `T` directly rather than
`Result!(T, JoinError)`.

## Thread start options

The default options value must be useful:

```d
struct ThreadStartOptions
{
    size_t stackSize;
}
```

`stackSize == 0` means use the platform default. A nonzero value is a requested
**minimum** stack reservation in bytes. The backend may round it upward to a
required page/granularity/platform minimum, but must never round it downward. A
value whose upward normalization overflows or cannot be represented/supported
returns `ThreadStartErrorKind.invalidConfiguration`. This definition avoids
pretending that every OS can provide an exact byte-sized stack.

Do not put worker arguments and start options in one ambiguous overload. Use
separate names:

```d
Thread.start!worker(args...);
Thread.startWith!worker(options, args...);

Thread.startRaw(function_, context);
Thread.startRawWith(options, function_, context);
```

The same `ThreadStartOptions` is accepted by `spawnWith` and
`ThreadScope.spawnWith`; those operations still create ordinary native threads.
A future **spawn-specific** options type is only justified if typed computation
state itself gains additional policy beyond native thread start options. Do not
add speculative fields before their portable semantics and backend behavior are
defined.

## Thread identity

`ThreadId` is an opaque, copyable value suitable for equality comparison and
diagnostics. It must not expose a POSIX `pthread_t`, Windows handle, or another
native type as its representation contract.

`Thread.id` identifies the represented thread. `currentThreadId` identifies the
calling thread.

Thread IDs are not owning handles and do not extend a thread lifetime.

`ThreadId.init` is the invalid/no-thread sentinel used by empty debug metadata.
On a supported backend, `currentThreadId()` and `Thread.id()` for a valid handle
must not return `.init`. Only equality/inequality and diagnostic formatting are
portable v1 operations; do not infer ordering from the representation. Reuse by
the operating system after a thread has terminated is permitted. A `ThreadId`
value previously obtained from a `Thread` remains an ordinary diagnostic value
after join/detach, but callers must not infer liveness or uniqueness from it
after the represented thread terminates.

## Thread utilities and naming

The foundational thread utility surface includes:

```d
ThreadId currentThreadId();
void yieldThread();
uint hardwareConcurrency();

Result!(void, ThreadNameError) setCurrentThreadName(String name);
Result!(void, ThreadNameError) Thread.setName(String name);
```

`hardwareConcurrency` returns the best available number of logical processors
that may execute concurrently.

Prefer a value that reflects processors currently available to this process or
calling thread (for example an affinity/cpuset restriction) when the platform
provides that information cheaply and truthfully; otherwise an online-machine
logical CPU count is an acceptable hint. The function is deliberately a hint,
not a topology API. V1 does not expose physical-core, NUMA, SMT, or cache
information.

Do not introduce mutable global caching solely for this function. Dynamic CPU
availability may change, and the library's base design avoids hidden process-wide
mutable policy state. If querying the best affinity-aware value proves too
expensive for a hot internal path, that internal path may use a cheaper backend
hint; it must not change the public meaning of `hardwareConcurrency()`.

A return value of zero means the platform could not provide a useful value;
callers must treat it as an unknown hint, not as "zero CPUs". The planned thread
pool may use this value as an input to its
default sizing policy, but the pool is not required to create exactly that many
workers.

`yieldThread` requests scheduler yield and remains distinct from `cpuRelax`. It
may be useful to polling/backoff code, but the normal mutex does not yield
between spinning and parking.

`yieldThread()` is best-effort and returns `void`; it does not guarantee another
specific thread runs or that any scheduling progress occurs before the caller is
scheduled again. On an unsupported backend where no scheduler-yield primitive is
available, a documented no-op fallback is acceptable because no correctness
protocol may depend on yield.

Thread naming is diagnostic functionality and should be supported early because
it materially improves debuggers, profilers, crash reports, and tests.

The public string is XTB UTF-8 `String`. V1 does not silently truncate, replace
invalid embedded NULs, or allocate merely to make a name acceptable. A name with
an embedded NUL is `invalidName`; a valid UTF-8 name exceeding the backend's
representable limit is `tooLong`. A backend may use bounded stack storage for a
terminator or encoding conversion.

The v1 public naming error shape is:

```d
enum ThreadNameErrorKind : ubyte
{
    unsupported,
    invalidName,
    tooLong,
    threadUnavailable,
    system,
}

struct ThreadNameError
{
    ThreadNameErrorKind kind;
    int nativeCode;
}
```

`threadUnavailable` covers the race in which a still-joinable handle represents
a worker that has already exited and the platform can no longer name it.
`Thread.setName` on an **empty/consumed** handle is instead a programming error;
there is no native thread to target. Native error codes are diagnostic opaque
values and are not portable equality keys. Naming APIs must not silently report
success when the platform rejects a name. Platform-specific length/character
restrictions are reported truthfully rather than hidden by silent truncation
unless a future explicitly named truncating API is introduced.

Naming a represented `Thread` is valid only while the backend can still address
that live thread. Calling `Thread.setName` on an empty, joined, or detached handle is a programming
error. On a still-joinable handle whose worker has already exited, the backend
must return `ThreadNameErrorKind.threadUnavailable` (or map the native race to
that portable kind) rather than treating the handle as caller misuse. It must
never target a reused thread ID accidentally. `setCurrentThreadName` is the most
portable operation and should be implemented first.

Once XTB has a stable monotonic-time abstraction, add `sleepFor(Duration)` and
`sleepUntil(Instant)` here rather than inventing threading-specific time units.

## Processor relaxation and `SpinWait`

`cpuRelax()` is the lowest-level busy-wait primitive:

```d
void cpuRelax();
```

It emits the appropriate processor hint for a deliberate short spin (for
example x86 `pause`) and does not ask the OS scheduler to deschedule the calling
thread.

`cpuRelax()` is not an atomic operation, compiler fence, or memory fence and
establishes no happens-before relationship. Polling code must still read its
condition through `Atomic` or another synchronization primitive. `yieldThread()`
likewise provides scheduling behavior, not memory ordering. It is useful in lock-free algorithms and internal fast paths.

`SpinWait` is a small public adaptive polling helper for conditions that do not
have a concrete parking/wakeup protocol:

```d
struct SpinWait
{
    void spin();
    void reset();
}
```

`SpinWait.init` is the initial round-zero state. The type is local policy state,
not a synchronization object; it may be copied/moved if ordinary D value
semantics permit, though sharing one mutable `SpinWait` instance concurrently is
not useful and is outside the contract.

Early `spin()` calls use one or more `cpuRelax()` hints. After sufficiently many
unsuccessful calls, `SpinWait` may escalate to `yieldThread()` to avoid burning
CPU indefinitely.

The initial v1 implementation should be deterministic and simple rather than a
learned/adaptive heuristic. Treat successive `spin()` calls as backoff rounds:

```text
round 0 -> 1  cpuRelax
round 1 -> 2  cpuRelax
round 2 -> 4  cpuRelax
round 3 -> 8  cpuRelax
round 4 -> 16 cpuRelax
round 5 -> 32 cpuRelax
round 6 -> 64 cpuRelax
round 7+ -> yieldThread
```

`reset()` returns the helper to round zero.

The internal round counter saturates once the yielding phase is reached; it must
not keep incrementing until integer wraparound. After saturation, each further
`spin()` yields until `reset()` is called. On a platform that truthfully reports
only one logical processor, `SpinWait` may yield immediately instead of spending
rounds actively spinning. These numbers are private tuning constants, not API
semantics, and may be changed after benchmarks; what is normative is bounded
active relaxation followed by scheduler yielding, never parking. `SpinWait` does
not park because it does not know which address/value transition would make a
park safe.

The normal `Mutex` deliberately does not use the yielding phase of public
`SpinWait`; it has a stronger park/wake protocol and therefore uses its own
bounded relax-then-park slow path described below.

## Memory model and atomics

The public atomic model follows the C/C++ memory model rather than inventing
XTB-specific orderings. V1 intentionally omits `memory_order_consume`; do not
add a `consume` enumerator or silently map one to another order. If D/XTB later
needs consume semantics, add them only through a separate design decision.

```d
enum MemoryOrder : ubyte
{
    relaxed,
    acquire,
    release,
    acquireRelease,
    sequentiallyConsistent,
}
```

The foundational API is conceptually:

```d
struct Atomic(T)
{
    T load(MemoryOrder order = MemoryOrder.sequentiallyConsistent) const;
    void store(
        T value,
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    );

    T exchange(
        T value,
        MemoryOrder order = MemoryOrder.sequentiallyConsistent,
    );

    bool compareExchangeWeak(
        ref T expected,
        T desired,
        MemoryOrder success = MemoryOrder.sequentiallyConsistent,
        MemoryOrder failure = MemoryOrder.sequentiallyConsistent,
    );

    bool compareExchangeStrong(
        ref T expected,
        T desired,
        MemoryOrder success = MemoryOrder.sequentiallyConsistent,
        MemoryOrder failure = MemoryOrder.sequentiallyConsistent,
    );
}
```

Integral atomics additionally provide `fetchAdd`, `fetchSub`, `fetchAnd`,
`fetchOr`, and `fetchXor` where meaningful.

Their conceptual signatures are:

```d
T fetchAdd(T value, MemoryOrder order = MemoryOrder.sequentiallyConsistent);
T fetchSub(T value, MemoryOrder order = MemoryOrder.sequentiallyConsistent);
T fetchAnd(T value, MemoryOrder order = MemoryOrder.sequentiallyConsistent);
T fetchOr (T value, MemoryOrder order = MemoryOrder.sequentiallyConsistent);
T fetchXor(T value, MemoryOrder order = MemoryOrder.sequentiallyConsistent);
```

As in C/C++, each returns the value that was stored immediately before the
operation. Pointer atomics support
load/store/exchange/CAS in v1; pointer arithmetic fetch operations are deferred.
V1 also provides `AtomicFlag` with:

```d
bool testAndSet(MemoryOrder order = MemoryOrder.sequentiallyConsistent);
void clear(MemoryOrder order = MemoryOrder.sequentiallyConsistent);
```

`testAndSet` is a read-modify-write operation; `clear` accepts only store-valid
orders. The initial
supported `Atomic!T` type set must be documented and compile-time constrained;
accepting arbitrary aggregates is not required for v1. `Atomic!T` is
non-copyable, and its `.init` state represents an atomic value initialized to
`T.init`.

V1 provides an explicit value constructor so callers can initialize an atomic
to a non-`T.init` value without a separate store, conceptually
`Atomic!T(value)`. It must not provide ordinary copy assignment that reads one
atomic and silently overwrites another. Changing an existing atomic value is done through
`store`/exchange/RMW operations. `AtomicFlag.init` is clear/false.

Atomics also expose blocking wait/notification in the style of C++20
`atomic::wait`:

```d
void wait(
    T oldValue,
    MemoryOrder order = MemoryOrder.sequentiallyConsistent,
);

void notifyOne();
void notifyAll();
```

`wait(oldValue)` blocks efficiently while the atomic compares equal to
`oldValue`. The implementation may wake spuriously internally, but it must
re-check the atomic and return only after observing a value that does not
compare equal to `oldValue`. As with C++ atomic wait, a transient change away
from `oldValue` and back to it may be missed; callers that need to observe every
transition require a generation/counter protocol rather than a bare value.

The wait operation performs atomic loads using `order`; therefore `release` and
`acquireRelease` are invalid wait orders. `notifyOne` and `notifyAll` carry no
independent memory ordering: publication must be performed by the atomic write
that changes the waited value. Waiting without changing the value is not a
reliable notification protocol.

The public atomic wait/notify surface is built on the same internal parking
backend used by higher-level blocking primitives. It is the preferred low-level
building block for countdown and generation-based synchronization.

Provide a thread fence matching the public memory-order model:

```d
void atomicThreadFence(MemoryOrder order);
```

For compare/exchange, failure writes the actually observed value back into
`expected`, matching C/C++ semantics. Failure ordering may not be `release` or
`acquireRelease` and may not be stronger than the success ordering. Invalid
order combinations are compile-time errors when statically knowable and
otherwise programming errors. The implementation uses compiler-supported
atomic primitives; it must not hand-roll architecture assembly unless a proven
backend gap requires it.

Do not promise lock-free behavior merely because a type is accepted. If
lock-free status matters, expose a truthful query or constrain the accepted type
set until the behavior is understood across supported compilers and targets.

### Atomic operation validity and v1 type support

The implementation must validate memory orders per operation, not merely accept
every `MemoryOrder` everywhere:

- `load`: `relaxed`, `acquire`, or `sequentiallyConsistent`;
- `store`: `relaxed`, `release`, or `sequentiallyConsistent`;
- read-modify-write (`exchange`, fetch operations, successful CAS): any ordering
  meaningful for a C/C++ read-modify-write operation;
- failed CAS and `wait`: never `release` or `acquireRelease`; and
- the failed-CAS ordering must not be stronger than its success ordering.

V1 should support scalar integral/enum/pointer atomics only where LDC can emit a
direct target atomic operation without an XTB hidden lock table. Pointer atomics
must support load/store/exchange/CAS. Pointer arithmetic fetch operations are not
required in v1; if later added, their units must be explicitly documented rather
than guessed.

Blocking `Atomic.wait` has a narrower portability constraint than non-blocking
atomic operations because Linux futex-style waits naturally target a 32-bit wait
word. The v1 API must therefore expose/encode a compile-time `waitSupported` (or
equivalent trait) and reject a `wait` instantiation that the active backend
cannot implement without hidden allocation/global waiter tables. The library's
own parking-based primitives should deliberately use a supported 32-bit wait
state. Do not promise that every `Atomic!T` accepted for load/store is also
waitable.

`Atomic.wait(old)` is used with the standard store-then-notify pattern:

```d
state.store(newValue, MemoryOrder.release);
state.notifyAll();
```

Changing the value without a corresponding notification is not required to wake
a thread promptly. Notification without a value/protocol change may wake a
waiter, but `wait` rechecks and continues if the full atomic value still equals
`old`.

All waited-on atomic objects are subject to the address-stability rule. Destroying
or moving an atomic while a waiter can still reference its address is a
programming error.

### Thread creation/join ordering

A successful thread creation publishes all state used to initialize the worker
before user worker code begins.

Worker completion synchronizes with a successful `join`. Reads performed by the
joining thread after `join` observe writes that happened-before worker
completion according to the synchronization contract.

`spawn` relies on this join synchronization to make its result storage visible;
it does not need a separate result-ready atomic solely for publication.

## Internal parking primitive

Blocking synchronization primitives share a small package-private parking API
conceptually equivalent to:

The parking contract is a **compare-and-sleep** operation, not an unconditional
sleep. The wait word is a backend-supported fixed-width atomic state (use a
32-bit word for the Linux v1 path). Immediately before sleeping, the backend
checks that the addressed word still equals `expected`; if it differs, `park`
returns without sleeping. This compare-and-sleep property is what closes the
classic check-then-sleep lost-wakeup race.

Untimed v1 parking may return because of a real wake, a signal/interruption, or a
backend spurious wake. Higher-level algorithms must always loop and recheck their
own state. Linux `EINTR` is treated as a spurious return, not a public error.
`wakeOne`/`wakeAll` do not themselves publish user data; the state transition and
its atomic memory order provide publication.

Use process-private futex operations on Linux because XTB's v1 synchronization
objects synchronize threads within one process. Do not accidentally promise
process-shared mutex/semaphore semantics.

A suitable v1 internal shape is:

```d
enum ParkResult : ubyte
{
    valueMismatch,
    wokenOrSpurious,
}

ParkResult park(uint* address, uint expected);
void wakeOne(uint* address);
void wakeAll(uint* address);
```

The pointer denotes storage that is accessed atomically by the caller/backend;
the exact `shared` annotation is part of the atomic/shared prototype gate. Timed
`parkUntil` is added later with the monotonic-time work rather than exposed as a
v1 placeholder.

Linux implements this with futex-style waiting. Windows can use
`WaitOnAddress`/`WakeByAddressSingle`/`WakeByAddressAll` where available.

The public mutex and condition-variable representations must not expose
`pthread_mutex_t`, `pthread_cond_t`, Windows `HANDLE`, or another platform ABI
unless a later native escape-hatch module explicitly opts into that coupling.

Timed parking is deferred until XTB has a stable monotonic-time abstraction.
Untimed primitives must be implemented first rather than inventing a
threading-specific duration type.

## Mutex

The default mutex is non-recursive:

```d
struct Mutex
{
    void lock();
    bool tryLock();
    void unlock();
}
```

A zero-initialized mutex is unlocked.

`Mutex` is non-copyable. A destructive move is permitted only before
publication; after publication its address is part of the wait/wake protocol.

`lock` and `unlock` do not return `Result`. Native errors indicating invalid
state are programming errors under the abstraction. Contention is an ordinary
part of `lock`, not an error.

The intended representation uses an atomic fast path and parking only under
contention. A compact three-state representation is suitable:

```text
0 = unlocked
1 = locked, no known waiters
2 = locked, contended
```

The numeric state is conservative rather than a precise waiter count. State `2`
means that an unlock must perform a wake because there **may** be a parked waiter;
it is legal for the state to remain contended temporarily even when no waiter is
currently asleep.

A reference state-machine shape for v1 is:

```text
fast acquire:
    CAS 0 -> 1 with acquire semantics

slow acquire:
    keep a local `contendedObserved` flag

    bounded spin:
        load state
        if state == 2:
            contendedObserved = true
        if state == 0:
            desired = contendedObserved ? 2 : 1
            CAS 0 -> desired with acquire semantics
            on success: own lock and return
        cpuRelax according to bounded backoff

    contended loop:
        # exchange both marks contention and attempts acquisition
        previous = exchange state -> 2 with acquire semantics
        if previous == 0:
            own lock in state 2 and return
        park(state, expected = 2)
        on wake/value-mismatch/spurious return, retry

unlock:
    previous = exchange state -> 0 with release semantics
    if previous == 2:
        wakeOne(state)
```

The important invariant is that a slow-path waiter which has observed/entered
contention never "forgets" that fact by acquiring as state `1`. Keeping state
`2` while such an owner holds the lock is conservative but necessary: another
waiter may still be parked and the next unlock must perform a wake. A woken
waiter that reacquires through the contended loop likewise owns the mutex in
state `2`.

Equivalent algorithms are allowed, but they must preserve the same invariants:
acquisition is an acquire operation, unlock is a release operation, parking
cannot miss the unlock transition, and a contended unlock wakes at least one
possible waiter. V1 does **not** promise FIFO/fair mutex acquisition.

Destroying/relocating a mutex while locked or while another thread may be
waiting/accessing it is a programming error. In checked builds destruction of a
nonzero state should be diagnosed where the concrete D lifetime makes such a
check practical; release builds need not retain owner metadata solely for this.

### Bounded spin then park

`Mutex.lock` should avoid a parking transition when a lock is released very
quickly, but it must not burn CPU indefinitely. V1 uses a bounded exponential
`cpuRelax()` backoff on the contended slow path and then parks. It does not call
`yieldThread()` between spinning and parking.

The initial tuning candidate is equivalent to:

```text
try acquire
1   x cpuRelax -> try acquire
2   x cpuRelax -> try acquire
4   x cpuRelax -> try acquire
8   x cpuRelax -> try acquire
16  x cpuRelax -> try acquire
32  x cpuRelax -> try acquire
64  x cpuRelax -> try acquire
park
```

The backoff is finite and capped: after reaching the maximum pause batch it does
not continue doubling or repeat the maximum forever; the next action is to mark
contention as required by the state machine and park. The exact sequence, cap,
and retry placement are internal platform-tuning policy rather than public API
semantics and must be benchmarked. V1 deliberately has no learned/per-mutex
spin budget.

When the platform reports exactly one logical processor, the mutex skips active
spinning and proceeds to the parking path because another thread cannot run
concurrently to release the lock. If processor count is unavailable, the
backend may conservatively skip spinning or use other reliable platform
knowledge; it must not require hidden mutable global policy state.

This mutex-specific algorithm is distinct from public `SpinWait`: `SpinWait` may
eventually yield because it has no park protocol, while `Mutex` can sleep on a
precise state transition and therefore goes directly from bounded relaxation to
parking.

### Checked ownership diagnostics

In `XTB_Checked` builds, `Mutex` records enough race-free owner metadata to
diagnose common lifecycle mistakes without making the release representation
larger. The diagnostics should catch at least:

- `lock()` by the thread that already owns this non-recursive mutex, reporting a
  recursive-lock programming error instead of hanging forever;
- `unlock()` of an unlocked mutex;
- a second `unlock()` after the mutex has already been released; and
- `unlock()` by a thread other than the current owner.

`tryLock()` remains a non-blocking probe: if the current thread already owns the
mutex it returns `false` rather than panicking merely because the attempted lock
would be recursive. The dedicated recursive-lock diagnostic applies to the
blocking `lock()` path where the mistake would otherwise become a self-deadlock.

Owner bookkeeping itself must not introduce a data race while trying to
diagnose one.

A practical checked representation is an atomic nonzero internal owner token
(`uintptr_t`/backend token), with zero meaning no owner. Do not require
`Atomic!ThreadId` if the opaque public `ThreadId` representation is not one of
the supported atomic scalar types. After successful lock acquisition, publish
the current token before returning to user code. On unlock, verify the token,
clear it while the caller still owns the mutex, then perform the release of the
actual lock state. Recursive blocking `lock()` checks the current token before it
would enter a self-deadlocking wait. Use an atomic/debug-owner representation or an equivalent ordering
protocol in which ownership metadata is published only after successful lock
acquisition and cleared while the current thread still exclusively owns the
mutex. All owner-only fields and checks disappear from `release-fast`.

A public recursive mutex is not part of v1. If one is eventually needed, it is a
separate `RecursiveMutex` type rather than a mode on `Mutex`.

## Condition variable (`CondVar`)

The public primitive is intentionally small:

```d
struct CondVar
{
    void wait(ref Mutex mutex);
    void notifyOne();
    void notifyAll();
}
```

`CondVar.init` is a valid condition variable with no waiters. The type is
non-copyable and address-stable after publication. The implementation is
allocation-free and does not wrap `pthread_cond_t` or another native condition
variable.

`wait(mutex)` requires the caller to own `mutex`. The waiter registers with the
condition variable while it still owns that predicate mutex, then releases the
predicate mutex as part of the registration commit. Before `wait` returns it
reacquires the same mutex. This registration-before-unlock ordering is the
semantic "atomically release and wait" guarantee: once a notifier can order
after the waiter's commit, that waiter is already represented in `CondVar`
state and cannot fall through an unlock-to-sleep lost-wakeup window.

In checked builds, calling `wait` without owning the supplied mutex is a
programming error. Normal `Mutex.unlock`/`Mutex.lock` ownership bookkeeping is
used when the waiter releases and reacquires the mutex; `CondVar` must not
invent a second owner state that can disagree with `Mutex`.

Spurious wakeups remain part of the public contract even though the v1
implementation normally returns from its blocking phase only after that
particular wait call has been notified. Callers always wait in a predicate loop:

```d
mutex.lock();
while (!ready)
    condition.wait(mutex);
// consume protected state
mutex.unlock();
```

Notifications are not stored as permits. `notifyOne`/`notifyAll` when there are
no registered waiters have no effect on a later `wait`. Neither notification
operation requires the notifying thread to hold the predicate mutex. Predicate
publication comes from the caller's synchronization protocol, normally the
predicate mutex's release/acquire edge; `CondVar` notification itself does not
create a separate user-data happens-before relation.

All concurrent waiters using one `CondVar` must use the same predicate mutex in
v1. `XTB_Checked` keeps only diagnostic mutex-address/active-waiter metadata for
this rule; it disappears from `release-fast` and is not required by the
correctness algorithm.

`notifyOne` provides no public FIFO/fairness guarantee. The v1 implementation
uses FIFO queue order internally to avoid gratuitous starvation, but the
awakened waiter still competes to reacquire the predicate mutex and callers must
not infer completion order from registration order. `notifyAll` affects exactly
the waiter population registered before its serialized queue snapshot; waiters
that register afterward are not part of that broadcast.

### V1 stack-backed waiter queue

V1 uses an explicit intrusive queue of waiter records. Every invocation of
`wait` creates its own waiter record in that call's stack frame:

```text
Waiter:
    32-bit atomic signaled word   // 0 -> waiting, 1 -> notified
    ForwardListHook!Waiter queueHook // IntrusiveQueue membership while registered

CondVar:
    internal state mutex
    IntrusiveQueue!(Waiter, "queueHook") waiters

    XTB_Checked only:
        associated predicate-mutex address
        active wait count
```

The queue stores pointers to stack records, but it does not own them and never
allocates them. The `wait` call itself owns its record until the call returns.
The implementation must therefore make the notifier-to-waiter lifetime
handshake explicit; merely setting `signaled = 1` is not enough because the
notifier still has to perform the wake operation on that same stack address.

This design is deliberately different from the earlier two-group/generation
proposal. A finite set of reusable 32-bit futex words either admits an eventual
ABA when a thread can be delayed arbitrarily long or requires quiescent reuse.
Quiescent reuse is mathematically strong, but it can make `notifyOne` wait for a
descheduled old waiter before a slot can be recycled. The per-wait stack record
avoids both compromises: a wait address is never reused during that wait's
lifetime, so there is no generation counter, wraparound arithmetic, or slot
reclamation on the notification path. The tradeoff is that `notifyAll` performs
one wake operation per registered waiter rather than one shared-group wake-all.
For XTB v1, correctness and simple progress reasoning take precedence over
optimizing very large broadcasts.

The implementation should use XTB core's `IntrusiveQueue` with one
`ForwardListHook!Waiter` embedded in each waiter record. `xtb_threading` already
depends on `xtb_core`, so duplicating queue head/tail manipulation inside
`CondVar` would add no useful isolation. `IntrusiveQueue` is allocation-free,
owns no waiter nodes, uses exactly one forward hook per node, and adds only
checked-build hook-membership diagnostics beyond the raw next pointer needed by
the queue. The queue remains protected entirely by the CondVar state mutex.

### Required invariants

The implementation must preserve all of these invariants:

1. **Registration precedes predicate-mutex release.** `wait` acquires the
   internal state mutex and enqueues its stack-backed waiter while it still owns
   the caller's predicate mutex. It releases the predicate mutex before
   releasing the internal state mutex. Therefore a notifier is serialized
   either before the waiter commits, in which case that notification need not
   affect the future wait, or after the commit, in which case the waiter is
   already in the queue.

2. **One wait call owns one unique wait address.** The `signaled` atomic belongs
   to the waiter record in that invocation's stack frame. It starts at zero,
   changes at most once to one, and is never reset or reused for another wait.
   Consequently there is no finite-width notification-generation ABA.

3. **The queue contains exactly the not-yet-notified registered waiters.** A
   notifier removes a waiter from the queue before making it signaled. A waiter
   never removes itself on the ordinary untimed path. With no cancellation or
   timeout in v1, there is therefore no race between notification and waiter
   withdrawal.

4. **`notifyOne` selects one waiter exactly once.** Under the internal state
   mutex it removes at most one queue node, stores `signaled = 1`, and performs
   the wake on that waiter's private atomic before releasing the internal mutex.
   A later notifier cannot select that same waiter again because it is already
   detached from the queue.

5. **`notifyAll` snapshots by serially draining the current queue.** While the
   internal state mutex is held, it repeatedly pops the queue front and signals
   that waiter. No later waiter can register until the mutex is released, so the
   drained population is exactly the population present at the broadcast's
   serialized snapshot.

6. **The atomic signal closes signal-before-park races.** A notifier stores one
   to the waiter's private atomic before waking it. If the waiter has not yet
   entered the parking backend, `Atomic.wait(0)` observes the changed value and
   does not sleep. If it is already parked, the wake makes it re-check. The
   signal word never returns to zero.

7. **The notifier retains waiter-node lifetime through its final pointer use.**
   The internal state mutex remains held through both `signaled = 1` and the
   corresponding wake call. The notifier must not keep a waiter pointer and
   access it after releasing that mutex.

8. **A notified waiter performs a lifetime barrier before returning.** After its
   private atomic becomes nonzero, `wait` reacquires the predicate mutex and
   then acquires/releases the internal state mutex before its stack waiter may
   go out of scope. Successfully acquiring the internal mutex proves that every
   notifier that could have held a pointer to that node has completed its final
   node access. In `XTB_Checked`, the same critical section may update active
   waiter diagnostics.

9. **The lifetime barrier must not make notification depend on waiter progress.**
   A notifier never waits for the awakened waiter to reacquire the predicate
   mutex or to execute the lifetime barrier. It only performs bounded queue
   bookkeeping and wake operations while holding the internal mutex. A stopped
   waiter may delay destruction of its own stack frame, but it cannot prevent a
   later `notifyOne` from notifying another registered waiter.

10. **Lock ordering is consistent.** A waiter begins with the predicate mutex,
    then acquires the internal state mutex; while still holding the internal
    mutex it releases the predicate mutex. After notification it reacquires the
    predicate mutex before taking the internal mutex for the final lifetime
    barrier. A notifier may itself hold the predicate mutex when calling
    `notifyOne`/`notifyAll`, but `CondVar` never acquires the predicate mutex
    internally from a notification operation. No internal state-mutex ->
    predicate-mutex acquisition edge is introduced.

11. **No queue node may outlive its wait frame, and no `CondVar` may outlive its
    users in reverse.** The lifetime barrier protects the stack node from late
    notifier access. Independently, moving/destroying the `CondVar` while
    another thread may be registering, waiting, notifying, or completing a
    wait remains a caller programming error under the general address-stability
    rule.

### Wait operation

Conceptually:

```text
caller owns predicate mutex
create zeroed Waiter on this wait() stack frame

lock CondVar state mutex
    checked: validate/record predicate-mutex association
    enqueue Waiter

    unlock predicate mutex
unlock CondVar state mutex

Waiter.signaled.wait(0)
// Atomic.wait internally tolerates backend-spurious wakes and returns only
// after the atomic is observed != 0.

lock predicate mutex

lock CondVar state mutex
    // lifetime barrier: no notifier can still access this Waiter
    checked: decrement active waiter count / clear association if last
unlock CondVar state mutex

return with predicate mutex held
```

Keeping the internal mutex held across enqueue + predicate unlock is essential.
Enqueueing and then dropping the internal mutex before releasing the predicate
mutex would still be correct for lost wakeups, but the stronger serialized
commit above gives one simple linearization story and matches the checked
association update.

The stack waiter is not an allocation and is not a borrowed user object. It is
private storage whose lifetime is exactly the dynamic extent of `wait`.

### `notifyOne`

Conceptually:

```text
lock CondVar state mutex

waiter = pop queue head
if waiter exists:
    waiter.signaled.store(1)
    waiter.signaled.notifyOne()

unlock CondVar state mutex
```

`IntrusiveQueue` is FIFO internally, so repeated notifications do not
intentionally prefer the newest waiter. This is an implementation policy, not a
public fairness guarantee.

The wake must occur while the internal mutex is still held. Consider a waiter
that observes `signaled = 1` immediately after the store, before the notifier
has executed the wake syscall. Without the final lifetime barrier and the
notifier-held mutex, that waiter could return and destroy its stack node while
the notifier still tries to wake that address. The mutex handshake removes this
use-after-lifetime race.

### `notifyAll`

Conceptually:

```text
lock CondVar state mutex

while IntrusiveQueue is not empty:
    waiter = IntrusiveQueue.popFront()
    waiter.signaled.store(1)
    waiter.signaled.notifyOne()

unlock CondVar state mutex
```

Each waiter has a different parking address, so v1 requires one wake operation
per waiter. `notifyAll` is therefore O(number of registered waiters) in both
queue traversal and parking-backend wake calls. This cost is explicit and must
not be hidden in the design. A future optimized broadcast protocol may replace
the representation only if it preserves the same no-lost-wakeup and
no-use-after-lifetime guarantees without adding hidden allocation or a finite
counter-wrap correctness assumption.

### Memory ordering and linearization

The caller's predicate data is synchronized by the predicate mutex, not by the
waiter's signal word. The private `signaled` atomic therefore needs only atomic
coherence for the wait protocol; relaxed store/load/wait ordering is sufficient
for v1. The notifier's internal-mutex unlock and the waiter's final
internal-mutex acquisition provide the node-lifetime synchronization edge.
Using stronger ordering on `signaled` must not be relied upon as a substitute
for that lifetime barrier, because the notifier performs the wake call *after*
the store.

A useful linearization model is:

- a `wait` becomes registered at its queue insertion while the state mutex is
  held; its predicate-mutex release is completed before another CondVar
  operation can acquire that state mutex;
- `notifyOne` chooses its waiter when it removes the queue head under the state
  mutex;
- `notifyAll` chooses its waiter population while it drains the current
  `IntrusiveQueue` under the state mutex; registration cannot interleave with
  that drain.

No notification operation itself publishes arbitrary user data. Callers still
modify/test their predicate under the predicate mutex and use the standard
predicate loop.

### Required tests

At minimum cover:

- `.init`, harmless notification with no waiters, and non-copyability;
- one waiter with `notifyOne`, including predicate-mutex reacquisition and
  predicate-data publication through that mutex;
- several waiters where one predicate permit plus `notifyOne` allows only one
  predicate-loop completion without depending on which thread is scheduled
  first;
- `notifyAll` with several registered waiters;
- notification with no registered waiter followed by a later waiter, proving
  notifications are not stored as permits for future waits;
- notification after registration but before the waiter enters `Atomic.wait`,
  proving signal-before-park cannot be lost;
- a deterministic lifetime test in which a notifier stores `signaled = 1` but
  deliberately delays its wake/final node access while the waiter attempts its
  final internal-mutex barrier, proving the waiter cannot outlive the notifier's
  pointer use;
- repeated bounded wait/notify cycles, including notifications performed while
  the notifying thread holds the predicate mutex, proving notification never
  waits for predicate-mutex reacquisition;
- `XTB_Checked` diagnostics for waiting without owning the predicate mutex and
  concurrent use of different predicate mutexes; and
- unsupported-backend `wait` failure without hidden allocation or a native
  condition-variable fallback.

Keep stress counts short. No correctness test may depend on scheduler fairness
or on the private FIFO selection policy becoming a public guarantee.

Timed waits remain deferred until the monotonic-time API is stable. A timed wait
must be able to remove its own still-queued stack node when timeout wins, racing
correctly against `notifyOne`/`notifyAll`; that withdrawal state is deliberately
absent from the untimed v1 protocol and must be designed explicitly rather than
bolted on.

## Semaphore

The counting semaphore surface is:

```d
struct Semaphore
{
    this(size_t initialPermits);

    void release(size_t count = 1);
    void acquire();
    bool tryAcquire();
}
```

`Semaphore.init` is valid and contains zero permits. `Semaphore(n)` starts with
exactly `n` immediately available permits. The type is allocation-free,
non-copyable, and address-stable after publication. Destroying or relocating it
while another thread can access it or while an acquire is active is a programming
error.

`release(0)` is a no-op. `release(n)` contributes exactly `n` permits. A
successful `acquire` or `tryAcquire` consumes exactly one. Overflowing the
`size_t` count of unreserved permits is an unconditional programming error; the
implementation must detect overflow before committing a wrapping arithmetic
update.

### Fast permit counter plus private waiter queue

V1 deliberately does **not** use the earlier proposed shared 32-bit
`wakeEpoch`. A forever-reused finite-width epoch brings back a theoretical ABA
case for a thread delayed between observing the epoch and entering the parking
operation. Adding enough generation/reclamation machinery to eliminate that ABA
would make this primitive more complicated than necessary.

Instead the semaphore combines:

```text
Atomic!size_t permits                 # available, unreserved permits
Mutex stateMutex                     # serializes slow registration/release
IntrusiveQueue!(SemaphoreWaiter, ...) waiters

SemaphoreWaiter (lives on acquire() caller's stack)
├── Atomic!uint state                 # queued / parking / signaled
└── ForwardListHook queueHook
```

`permits` is independent of parking width and therefore preserves the full
`size_t` public count on both 32-bit and 64-bit targets. Each blocking acquire
owns a unique one-shot 32-bit wait word for only that call, so no wait word is
reused across logical semaphore generations and there is no finite-width
wake-counter wrap/ABA problem. The intrusive queue allocates nothing; it links
only stack nodes whose lifetime is explicitly protected by the protocol below.

The central invariant is:

> **If the waiter queue is non-empty, `permits == 0`.**

A permit represented in `permits` is unreserved and may be consumed by the fast
path. A permit handed directly to a queued waiter is already reserved for that
waiter and is never inserted into `permits`. Thus a racing `tryAcquire` cannot
steal a permit that `release` has selected for an existing blocked acquire.

### `tryAcquire`

`tryAcquire` is a true non-blocking operation: it never takes `stateMutex` and
never parks. It repeatedly CAS-decrements `permits` only while the observed value
is nonzero. Successful consumption uses acquire ordering; failure may use relaxed
loads/CAS failure ordering.

This means internal slow-path mutex contention cannot make `tryAcquire` block.
Returning `false` means no unreserved permit was successfully consumed during
the operation; permits already reserved for queued waiters are intentionally not
available to it.

### `acquire`

`acquire` first executes the same atomic permit-consumption fast path as
`tryAcquire`. If it succeeds, no internal mutex or parking operation is touched.

After a fast-path miss, on a parking-supported backend it performs:

```text
lock stateMutex
    recheck permits with the same atomic consume operation
    if successful:
        unlock stateMutex
        return

    enqueue this acquire's stack waiter
unlock stateMutex

commit waiter state from queued -> parking
if release already changed it to signaled:
    do not park
else:
    Atomic.wait while state == parking

lock + unlock stateMutex   # waiter-node lifetime barrier
return
```

The second permit check is mandatory. It closes the race in which `release` adds
an unreserved permit after the first fast-path miss but before slow-path
registration. Registration and release selection are serialized by `stateMutex`,
so after that recheck the acquire either consumes a real permit or is present in
the queue before a later release can decide where its permits go.

The waiter state is one-shot:

```text
queued   = registered, but has not committed to entering Atomic.wait
parking  = waiter intends to park on this private word
signaled = one permit has been handed directly to this waiter
```

The waiter CASes `queued -> parking`. `release` atomically changes either
`queued` or `parking` to `signaled` with release ordering. If `release` observes
`queued`, no wake syscall is needed: the waiter's CAS observes `signaled` and it
never parks. If `release` observes `parking`, it calls `notifyOne`; a wake before
the kernel sleep point remains safe because `Atomic.wait`/parking compares the
changed value before sleeping. The waiter observes `signaled` with acquire
semantics, establishing publication for a directly handed-off permit.

On a backend without parking support, the atomic fast path remains functional.
An `acquire` that finds an available permit succeeds normally. Only an acquire
that would actually need to block fails through the explicit unsupported-platform
panic. `release` and `tryAcquire` therefore remain usable without a parking
backend.

### `release`

`release(count)` takes `stateMutex` on a parking-supported backend and consumes
the requested count in this order:

1. while both `count != 0` and queued waiters exist, pop the oldest waiter and
   hand one permit directly to it by changing its private state to `signaled`;
2. decrement the local release count for each direct handoff; and
3. add any remainder to `permits` using a release CAS with overflow checking.

The FIFO queue is a private selection policy, not a public fairness guarantee. A
signaled thread must still be scheduled and complete its acquire-side lifetime
barrier, so completion order is unspecified. The useful invariant is only that a
permit selected for an already queued waiter cannot be barged by the atomic fast
path.

Adding the remainder to `permits` uses release ordering. A fast-path
CAS-decrement uses acquire ordering. Direct handoff uses a release update of the
waiter's private state paired with the acquiring waiter observing that state with
acquire ordering. Thus writes sequenced before the providing `release` happen
before code sequenced after the corresponding successful acquire. Wake calls
themselves carry no publication ordering.

### Stack waiter lifetime

As with `CondVar`, the intrusive queue stores pointers to waiter records on other
threads' stacks, so the final pointer use must be proven before `acquire` returns.
`release` retains `stateMutex` through its final access to each selected waiter,
including any required `notifyOne`. After observing `signaled`, the waiter
acquires and releases `stateMutex` before returning. That mutex crossing proves
that no releaser can still hold a live pointer to the waiter node when its stack
lifetime ends.

The releaser never waits for the selected waiter to run; it performs only its
normal bounded queue/state work and wake syscall while owning `stateMutex`. This
avoids the progress problem of a reclamation scheme that would wait for a
descheduled waiter before reusing shared parking storage.

### Required `Semaphore` tests

At minimum cover:

- `.init`, `Semaphore(n)`, `release(0)`, `release(n)`, and exact
  `tryAcquire` consumption;
- `tryAcquire` while `stateMutex` is deliberately held, proving the public
  non-blocking path does not take that mutex;
- release/acquire publication through both stored permits and a direct waiter
  handoff;
- deterministic release after waiter registration but before the waiter commits
  to parking, proving the wake is retained without a wake syscall requirement;
- deterministic waiter-node lifetime synchronization where the waiter observes
  `signaled` before the releaser's final wake/pointer access completes;
- several waiters with `release(k)` proving exactly `k` permits become
  consumable and no permit is duplicated;
- repeated bounded contention with an initial capacity greater than one, proving
  concurrent critical-section occupancy never exceeds the permit count;
- overflow at `size_t.max` as an unconditional fatal programming error;
- non-copyability/address-stability expectations; and
- unsupported-backend behavior where non-blocking permit operations still work
  and only an acquire that must block fails explicitly.

Keep stress counts bounded. Do not make correctness depend on FIFO scheduling or
on a particular kernel wake order.

## Latch

`Latch` is the foundational public countdown primitive. It is one-shot: its
count is established once and may only decrease. It never resets or begins a
second generation.

```d
struct Latch
{
    this(size_t count);

    void countDown(size_t count = 1);
    void wait();
    bool tryWait() const;
}
```

`Latch.init` is valid and represents a completed latch with count zero. A
constructed `Latch(n)` starts at `n`. `countDown` atomically subtracts from the
remaining count; decrementing below zero is a programming error. Transitioning
from one to zero wakes all waiters. Once zero is reached it remains zero for the
rest of the latch lifetime.

`wait` blocks until the count is zero. `tryWait` reports whether it is already
zero without blocking.

`countDown(0)` is a no-op. The decrement operation must not transiently wrap an
unsigned counter and then "detect" underflow afterward; use a CAS/subtraction
protocol that proves the requested decrement was no greater than the current
count before committing it. `Latch` is non-copyable and address-stable once
published. Completion publishes all writes that happen-before the
corresponding countdown operations to a waiter that returns from `wait`.

The implementation should use the internal `CountdownState` and atomic
wait/notify path rather than expose a condition variable internally. It may wait
directly on the count only when that atomic width is natively wait-supported;
otherwise use the separate wake-epoch pattern described below.
The first implementation should be small enough that its countdown/wakeup
algorithm can be stress-tested independently before reusable generation
primitives are introduced.

## Internal countdown and generation machinery

`Latch`, `WaitGroup`, and `Barrier` should share narrow package-private state
machines rather than being implemented directly in terms of one another. In
particular, `Latch` must not contain a public `WaitGroup`: the simpler one-shot
primitive should not inherit the more complicated reuse rules of the dynamic
primitive.

A suitable layering is conceptually:

```text
Atomic.wait / notify
        |
        +-- CountdownState --------> Latch
        |
        `-- GenerationWaitState ---> WaitGroup
                                  `-> Barrier
```

`CountdownState` owns only the monotonic count-to-zero mechanics.
`GenerationWaitState` additionally tracks a changing generation (or an equivalent
ABA-safe phase token) so waiters from one completed phase cannot be confused by
immediate reuse in the next phase. These are internal implementation concepts,
not public types.

The logical counter/participant width does not have to equal the backend's
waitable word width. In particular, a suitable portable pattern is:

```text
Atomic!size_t logicalCount       # full public count/range
Atomic!uint   wakeEpoch          # 32-bit parkable generation/notification word
```

Waiters snapshot `wakeEpoch`, recheck the logical predicate, and only then call
`wakeEpoch.wait(snapshot)`. The thread that performs the semantic transition
(count reaches zero / phase completes) updates the logical state first, advances
`wakeEpoch`, and notifies. This pattern avoids restricting public `size_t`
counts to 32 bits merely because Linux futex waits use a 32-bit address.

A modulo-width wake epoch is safe only when the surrounding state machine proves
a waiter cannot remain associated with an old phase across enough phase changes
to become ambiguous. `WaitGroup` explicitly forbids starting the next generation
until old waiters have returned; a barrier waiter spans one generation. For
protocols such as condition variables that may receive arbitrarily many
notifications while one waiter is delayed, retain/recheck a wider logical
generation in addition to the waitable epoch if needed.

For `GenerationWaitState`, the 32-bit waitable word is itself the generation.
The `WaitGroup` reuse rule and `Barrier` participation rule prove that a valid
waiter cannot remain associated with one phase across enough phase completions
for 32-bit wrap to become ambiguous. Do not add a second wide generation unless
a future consumer permits waiters to fall arbitrarily many phases behind. The
separate full-width `size_t` value remains necessary for public work and
participant counts; it is not a second phase identifier.

## Wait group

`WaitGroup` tracks a dynamically registered set of outstanding operations and
may be reused across generations:

```d
struct WaitGroup
{
    void add(size_t count = 1);
    void done(size_t count = 1);

    void wait();
    bool tryWait() const;
}
```

`WaitGroup.init` is valid with an outstanding count of zero. `add` registers
work and `done` completes it.

`add(0)` and `done(0)` are no-ops. `wait()` called while the count is already
zero returns immediately and does not itself open a generation. A positive
zero-to-positive `add` is the operation that opens a generation. Completing more
work than has been registered is an unconditional state-integrity programming
error. Multiple concurrent waiters are permitted.

A generation begins when the outstanding count transitions from zero to a
positive value and completes when it returns to zero. Reuse follows rules
modelled after Go's `sync.WaitGroup`:

- a positive `add` that begins a new generation (zero to positive) must happen
  before any `wait` for that generation;
- while the count is already positive, additional `add` operations may be used
  to register child work, including from workers participating in the current
  generation;
- `wait` returns when the generation's count reaches zero; and
- when reusing a wait group, every `wait` for the previous generation must have
  returned before the next zero-to-positive `add`.

Violating the generation/reuse rules is a programming error.

The implementation should track enough waiter/generation state to diagnose the
most dangerous zero-to-positive reuse race in checked builds and, more
importantly, to avoid lost wakeups even when misuse is not diagnosed in release.
`WaitGroup` is non-copyable/address-stable after publication. It provides no
implicit relationship between the lifetime of registered work and the lifetime
of arbitrary objects; the count is only synchronization bookkeeping. The internal
generation token exists specifically to make fast completion and immediate
reuse distinguishable to waiters and to avoid ABA-style wakeup bugs.

`WaitGroup` is more flexible and correspondingly easier to misuse than
`Latch`; APIs with a fixed, one-shot count should prefer `Latch`.

A `done` that contributes to completion publishes preceding worker writes with
release semantics. A `wait` that returns for that generation has acquire
semantics and observes writes published by all completion operations in that
generation. `add` changes bookkeeping; it is not a substitute for publishing the
work's produced data.

A suitable semantic state model contains an outstanding `count`, a `generation`
(or wake epoch), and enough waiter bookkeeping to enforce/reason about reuse:

```text
add while count > 0:
    increase count, remain in current generation

last done (count -> 0):
    publish completion
    advance generation/wake epoch
    notifyAll waiters

wait while count > 0:
    register/snapshot current generation
    recheck count after registration
    wait for generation change or count == 0
    unregister before returning

new generation (0 -> positive):
    permitted only after previous-generation waiters are gone
```

The concrete representation may combine count/waiter fields into one CAS word or
use several atomics, but it must close the race where completion occurs between
a waiter deciding to sleep and actually parking. Do not implement `wait` as a
bare `while (count != 0) count.wait(...)` if the chosen count width is not
wait-supported or if generation reuse can make that ambiguous.

`add` overflow and `done` underflow must be prevented before committing the state
change in every build. `tryWait()` is non-blocking; when it observes zero it uses
acquire semantics equivalent to a completed `wait`.

## Barrier

`Barrier` is a reusable phase synchronization primitive for a fixed initial
number of participants:

```d
struct Barrier
{
    this(size_t participants);

    void arriveAndWait();
    void arriveAndDrop();
}
```

The participant count supplied to the constructor must be greater than zero.

`Barrier.init` is a valid inert/permanently-complete zero-participant state, but
no arrival operation is valid on it. The explicit `Barrier(participants)`
constructor requires `participants > 0`; passing zero is a programming error.
This preserves a valid D zero state without pretending a zero-participant
barrier can later be activated.
Each generation completes when every current participant has arrived. The final
arrival advances the generation and wakes the other participants; all returning
participants then proceed in the new phase. Writes sequenced before an arrival
happen-before work performed after the corresponding generation completes.

`arriveAndDrop` counts as the caller's arrival in the current generation and
permanently removes that participant from subsequent generations.

`arriveAndDrop` does **not** wait for the other participants; after atomically
recording this generation's arrival and reducing the expected participant count
for future generations, it returns. `arriveAndWait` is the operation that waits
for phase completion. A caller must conceptually own one participant slot for
each arrival in a generation; duplicate/missing arrivals are programming errors
that cannot necessarily be attributed to a specific thread without extra debug
state. If all participants eventually drop, the barrier becomes permanently
complete and no further arrivals are valid.

The first public API deliberately omits split `arrive`/`wait(token)` operations,
completion callbacks, and dynamic participant addition. They can be added later
only if a concrete use case justifies the extra state-machine complexity.

`Barrier` should reuse the same internal generation machinery proven by
`WaitGroup`, while retaining its own fixed-participant public contract.

`Barrier` is non-copyable/address-stable once used. V1 does not promise that the
same OS thread corresponds to the same participant slot in every generation;
participant identity is a logical caller obligation, not a stored thread ID.

A useful semantic model is:

```text
currentExpected   # participants expected in this generation
remaining         # arrivals still needed in this generation
nextExpected      # participants expected after accumulated drops
generation/epoch  # changed exactly when a phase completes
```

At construction, all three counts equal the participant count. `arriveAndWait`
atomically consumes one `remaining` slot. If it was the final arrival, that
caller completes the phase: set the next generation's expected/remaining count
from `nextExpected`, advance the generation/epoch with release publication, and
notify all waiters; the final arriver itself does not park. Otherwise it waits
for the generation to change and returns with acquire semantics.

`arriveAndDrop` atomically consumes one current `remaining` slot **and** one
future `nextExpected` slot, then returns without waiting unless it happens to be
the final arrival (in which case it performs the same phase-completion reset and
wake before returning). When `nextExpected` becomes zero at phase completion,
the barrier enters the permanently complete state.

The concrete representation must make concurrent arrivals/drops linearizable;
separate non-atomic updates to `remaining` and `nextExpected` that can observe an
inconsistent phase are not acceptable. A packed CAS state or a carefully locked
internal state transition are possible designs, but v1 must remain allocation
free.

## Read/write lock

Use explicit operation names:

```d
struct RwLock
{
    void lockRead();
    bool tryLockRead();
    void unlockRead();

    void lockWrite();
    bool tryLockWrite();
    void unlockWrite();
}
```

Do not use ambiguous `lock` overloads whose meaning depends on an enum or tag.

V1 uses a **writer-preferring** policy: once a writer is queued, new readers do
not continually bypass it; existing readers drain, then a writer is allowed to
make progress.

The implementation therefore needs, conceptually, three pieces of state: an
active-reader count, whether a writer currently owns the lock, and whether one
or more writers are waiting (or an equivalent encoded state). `lockRead` may
acquire only when no writer owns the lock and no writer is queued. `lockWrite`
first makes writer intent visible so new readers stop entering, then waits for
the active-reader count and writer-active bit to clear. `unlockWrite` should
prefer waking a waiting writer; when no writer is waiting it may wake blocked
readers. Equivalent compact bitfield algorithms are allowed.

This prevents unbounded writer starvation under a stream of new readers. V1
does not promise strict FIFO ordering, and a sustained stream of
writers may delay readers.

There is no upgrade/downgrade API in v1.

The v1 `RwLock` is non-recursive in **both** modes. Reacquiring a read lock while
the same thread already holds a read lock is outside the contract as well; this
restriction avoids the writer-preference self-deadlock problem where a queued
writer closes the reader gate between nested read acquisitions. Per-reader owner
tracking is not required, so this misuse may not be diagnosed.

`tryLockRead`/`tryLockWrite` are immediate probes and never park. A failed probe
returns `false` without changing lock ownership. A successful probe has the same
acquire ordering as the corresponding blocking lock.

Calling `lockWrite` while the caller holds a read lock, calling `lockRead` while
the caller holds the write lock, attempting to convert modes without unlocking,
or recursively acquiring the write lock is outside the valid contract. Checked
builds should diagnose self-deadlocking writer-owner cases where the inexpensive
writer owner token makes that possible. Per-reader owner tracking is not required
because it would need disproportionate metadata.

`unlockRead` when no read ownership/count exists and `unlockWrite` when no writer
is active are unconditional state-integrity programming errors; the
implementation must not underflow/corrupt its state in release. Distinguishing a
wrong-thread writer unlock from the actual writer requires checked owner metadata
and may therefore be a checked-only diagnostic.

`RwLock.init` is unlocked. The type is non-copyable/address-stable after
publication. Read acquisition has acquire semantics; each read unlock performs
the release/RMW ordering required so a subsequent writer can observe every
reader that drained before it acquired. Write unlock is a release operation, and
write acquisition is exclusive with all readers/writers.

## One-time initialization

The low-level primitive is a zero-valid-state `Once` object. The preferred
public convenience is:

```d
callOnce!initializer(once, args...);
```

Its declaration takes the synchronization object as a genuine free-algorithm
receiver:

```d
void callOnce(alias initializer, Args...)(ref Once once, Args arguments);
```

It must remain `nothrow @nogc` and allocation-free.

The v1 `initializer` is a context-free module/static function alias, matching the
no-hidden-context policy used by the typed thread adapters. Its explicit
arguments are normal by-value arguments to `callOnce`; their expressions are
evaluated by the caller even if another thread has already won initialization.
Only the winning caller invokes the initializer function itself.

Concurrent calls are allowed to instantiate `callOnce` with different
initializer functions/arguments, but exactly one winner runs; callers must
accept that the winner determines the side effects. Code that requires one
specific initializer should consistently call that initializer rather than rely
on scheduling order.

Because XTB has no exceptions, there is no exception-poisoning behavior to
emulate. Initializer parameters use by-value transport; `ref`, `out`, `lazy`,
and preview-sensitive `in` parameters are rejected. Callers pass pointers or
slices explicitly when the initializer must access external state.

The reference `Once` state machine is:

```text
0 = uninitialized
1 = initialization in progress
2 = initialized
```

`callOnce` attempts `0 -> 1`; the winner invokes the supplied initializer
synchronously on the caller thread that won the state transition; `callOnce`
never creates another thread. The winner then publishes `2` with release
semantics and wakes all waiters. Losers that observe
`1` wait; callers that observe `2` return with acquire semantics. Because the
initializer is `nothrow` and `panic` is process-fatal, there is no recoverable
"poisoned" state. The v1 initializer returns `void`; non-void results belong in
`OnceCell!T`.

Recursive `callOnce` on the same `Once` from its own initializer would otherwise
self-deadlock. Checked builds should record the initializing thread cheaply and
panic with a recursive-once diagnostic when practical. `Once` is non-copyable
and address-stable once published.

If initialization itself can fail recoverably, that policy must be represented
explicitly rather than overloading the meaning of `Once`.

A later `callOnceResult` may be added only after its retry/failed-state
semantics are designed.

## `OnceCell!T`

`OnceCell!T` is the typed, allocation-free value form of one-time
initialization. It owns uninitialized storage for `T` plus the synchronization
state required to construct that value exactly once:

```d
struct OnceCell(T)
{
    @disable this(this);

    bool isInitialized() const;

    Option!(T*) tryGet() return;
    Option!(const(T)*) tryGet() const return;

    ref T getOrInit(alias initializer, Args...)(Args args) return;
}
```

`isInitialized()` is non-blocking. A `true` result is observed with acquire
semantics so publication of the stored `T` is visible to subsequent synchronized
accesses.

`OnceCell.init` is uninitialized. `getOrInit` executes exactly one successful
initializer, stores the resulting `T` directly in the cell, and returns a
reference to the stored value. Concurrent callers that lose the initialization
race wait and receive the same stored object.

`tryGet` never blocks: before publication it returns `none()`, and after
publication it returns `some(pointerToStoredT)`. The returned pointer/reference is
borrowed from the cell and is valid only while the cell remains alive and at the
same address.

The initializer is a context-free alias callable in v1 and must return a value
constructible as `T` under `nothrow @nogc`.

A `ref`/borrowed initializer return is rejected: the cell owns its own `T` and
must construct that owned value in its internal storage. For move-only `T`, the
initializer result is moved directly into the cell and no copy requirement is
introduced. Exactly whichever concurrent caller
wins the initialization CAS has its initializer invoked; other callers' function
bodies are not invoked. Therefore code should not race semantically different
initializers against the same cell unless it intentionally accepts "first
winner defines the value" semantics. Ordinary D evaluation of argument
expressions still occurs before entering `getOrInit`, even for a caller that
loses the race.

Publication uses acquire/release ordering so every caller observing
initialization also observes the fully constructed `T`.

This synchronization only protects **initialization/publication**. Returning
`ref T`/`T*` does not make later mutation of `T` automatically thread-safe.
Concurrent mutation after initialization requires atomics, a mutex, immutable
usage, or another caller-supplied synchronization protocol.

The initializer and every construction/move/destruction step required by the
cell must satisfy `nothrow @nogc`. A panic during initialization remains
process-fatal. Recursive `getOrInit` on the
same cell from its winning initializer would otherwise self-deadlock; checked
builds should diagnose that case using the same initializing-owner strategy as
`Once` when practical. Recoverable initialization failure/retry semantics are
deliberately not overloaded onto this v1 type; a future `OnceCellResult` or other
explicit API can be designed if needed.

The cell destroys `T` exactly once when an initialized cell is destroyed. The
caller must not destroy or relocate a cell while another thread may be accessing
it. Moving an unpublished/unobserved cell may be permitted by the concrete D
implementation, but once the cell's address or contained reference is shared
across threads its storage is treated as stable for the rest of that concurrent
lifetime.

## Guards

RAII lock guards are convenience wrappers over the raw primitives, not the only
way to use them:

```d
LockGuard!Mutex
ReadLockGuard!RwLock
WriteLockGuard!RwLock
```

They must be allocation-free and non-copyable. Their destructors unlock and
therefore must never fail routinely.

V1 guards are simple owning lock tokens: construction acquires the corresponding
lock mode, the guard stores a pointer/reference to the stable lock object, and
destruction releases exactly that mode.

The intended usage is lexical, for example:

```d
auto guard = LockGuard!Mutex(&mutex); // locks mutex
// protected region
// guard destructor unlocks
```

The exact constructor/factory spelling may follow existing XTB owning-wrapper
conventions, but acquiring-on-construction and releasing-on-destruction are
normative.

A guard that owns a `Mutex` or write lock is thread-affine while it owns that
lock: it may be moved between variables on the **same thread**, but must not be
transferred to another thread and destroyed there, because the underlying lock
must be released by its owning thread. Checked mutex/RwLock owner diagnostics
should catch this misuse where available. Do not describe guard movability as
permission for cross-thread transfer. Guards may be moved only by transferring
ownership to an empty destination; the moved-from guard becomes empty. V1 does
not need `adopt_lock`, deferred-lock, manual `release`, or multi-lock
constructors. Keep those policies out until a concrete use case exists.

The raw `lock`/`unlock` surface remains public for code whose lifetime cannot be
expressed conveniently with a lexical guard.

## `shared` policy

The library uses atomic/compiler primitives where actual cross-thread shared
state requires them, but it does not force every object protected by a mutex
into an ergonomically hostile `shared(T)` object graph without a demonstrated
safety benefit.

The exact interaction between D's `shared`, `Atomic!T`, mutex-protected data,
and typed worker arguments must be validated with focused compiler experiments
before freezing annotations across the API.

This is a **prototype gate**, not permission for each implementer to choose a
different public qualifier scheme. Before committing the first public headers,
compile small tests for mutable/const/shared receivers, pointer parameters,
`inout`, and UFCS/template inference under the supported LDC. Record the chosen
annotations in this document/API comments, then apply them consistently across
all primitives. Do not add `shared` casts merely to silence the compiler without
a written synchronization argument.

Pointers passed to another thread are explicit borrowed shared-state channels.
The library cannot prove the pointed data is synchronized; that remains the
caller's responsibility.

Slices, delegates, and aggregate fields that contain pointer-like references
follow the same rule even when the outer value is captured by value. Value
capture does not imply deep-copy or ownership transfer of referenced storage.

## Native-thread environment and TLS

XTB guarantees only the portable state explicitly described by this document.
Backends must not accidentally promise preservation or reset behavior for
platform-specific thread state such as signal masks, floating-point control
state, affinity, priority, scheduler policy, locale-related TLS, or similar
process/runtime facilities unless that behavior is deliberately added to the
public contract. Platform defaults/inheritance may differ.

D/compiler TLS and runtime assumptions require focused LDC experiments before
implementation is considered complete.

The minimum experiment should create an XTB raw thread (without druntime thread
startup) and read/write a simple module-level D TLS variable independently from
the parent, then repeat for TLS reached through a templated module. Verify that
address/value isolation works and document whether any TLS destructor/finalizer
behavior exists under `-betterC`; v1 must not rely on TLS destructors unless that
behavior is proven. `__gshared` is process-global and is not evidence that D TLS
works. In particular, threads created without
druntime startup must not access language/runtime TLS facilities unless XTB has
verified that the relevant storage is correctly initialized under `-betterC`.
This concern is separate from XTB's own optional `ThreadContext`. Until proven
otherwise, worker code should be written as though only explicitly passed state
and verified BetterC-safe TLS facilities are available.

POSIX `fork` after the process has become multithreaded is outside the first
implementation contract. The threading library does not attempt to make locks,
parking state, allocators, or spawned-computation state fork-safe.

## Error handling policy

Use `Result` only where failure is an expected external/runtime outcome.

Examples:

```d
Result!(Thread, ThreadStartError) Thread.startRaw(...);
Result!(Thread, ThreadStartError) Thread.start!worker(...);
Result!(Thread, ThreadStartAllocError) Thread.startRawAlloc(...);
Result!(Thread, ThreadStartAllocError) Thread.startAlloc!worker(...);
Result!(JoinHandle!T, SpawnError) spawn!worker(...);
Result!(void, SpawnError) ThreadScope.spawn!worker(...);
```

Do not add `Result` to operations where failure means a broken lifecycle
contract:

```d
int Thread.join();
void Thread.detach();
void Mutex.lock();
void Mutex.unlock();
bool Mutex.tryLock();
void CondVar.notifyOne();
```

A worker that has an expected domain failure returns its own `Result`:

```d
Result!(Config, ParseError) loadConfig(Path path) nothrow @nogc;
```

`spawn` preserves that result as the computation value instead of creating a
second thread-specific error layer around it.

## Planned thread pool

A thread pool is an important planned higher-level feature, but it is not part
of the primitive synchronization contract in this document. It must be built on
the thread, parking, synchronization, and typed-result facilities after those
semantics are proven.

`hardwareConcurrency()` exists partly to provide a portable logical-CPU hint for
future pool sizing, but the pool must treat it as policy input rather than an
exact required worker count. In particular, a zero result means unknown, and
applications may intentionally choose fewer or more workers than the hardware
hint.

Do not freeze a pool API here. Queue type, boundedness/backpressure, task result
transport, allocator ownership, shutdown/drain/cancel semantics, worker naming,
local queues, and work stealing all require a separate design pass. The initial
thread pool should not be smuggled into `Thread`, `spawn`, or `threadScope` by
adding speculative fields or behavior to those lower layers.

## Ownership summary

### `Thread.startRaw`

```text
function pointer: copied
void* context: copied, pointee remains caller-owned
Thread: owns native join obligation
```

### `Thread.startRawAlloc`

```text
function pointer + void* context: copied into allocator-backed adapter state
user context pointee: remains caller-owned
start allocation: transferred to child and freed before user worker entry
allocator: borrowed until child frees start allocation; must support child-thread deallocation
Thread: owns native join obligation
```

### `Thread.start!worker`

```text
arguments: copied/moved into start packet, then into worker stack
start packet: borrowed only until child signals capture
Thread: owns native join obligation
allocation: none
```

### `Thread.startAlloc!worker`

```text
arguments: copied/moved into allocator-backed typed capture state
captures: converted on starting thread before native creation
start allocation: transferred to child and freed before user worker entry
allocator: borrowed until child frees start allocation; must support child-thread deallocation
Thread: owns native join obligation
```

### `spawn!worker`

```text
arguments: copied/moved into stable allocated state
result: constructed in stable allocated state by worker
JoinHandle: owns Thread + spawn-state allocation + join obligation
join: moves result out and frees state
allocation: exactly through caller-supplied Allocator*
detach: unsupported
```

### `threadScope` / `scope.spawn!worker`

```text
scope allocator: borrowed for the lexical scope lifetime
child node: allocated and later deallocated with that same allocator
allocation/deallocation thread: always the scope-owning thread
borrowed/ref arguments: bounded by structured child lifetime
ThreadScope: owns every successfully started child immediately
scope exit: joins all children, destroys nodes, deallocates nodes
detach: unsupported
worker result: void in v1
```

## Prototype gates before public API freeze

The following questions are intentionally not guessed. They must be answered by
small compiler/backend experiments before the corresponding public declaration
is considered frozen:

1. **Scoped structured-borrow syntax:** prove the chosen `threadScope` callback
   form stays stack/scoped under `-betterC`, does not require a GC closure, and
   prevents the `ThreadScope` capability from escaping as far as D's lifetime
   system can express. The semantic contract in this document is fixed even if
   the exact call syntax changes.
2. **Parameter storage-class introspection:** **completed for typed starts on
   LDC 1.42.0 / DMD 2.112.1.** `ref`, `out`, and `lazy` are explicit aliasing
   modes and are rejected. `scope`/`return` can decorate by-value transport.
   `in` changes from value-like behavior to caller aliasing under `-preview=in`,
   so v1 typed starts reject `in` in all build modes. Scoped-start borrowing
   still needs its separate lifetime prototype before `threadScope` is frozen.
3. **`shared`/`inout` annotations:** establish which public methods can remain
   `@safe`/qualifier-preserving without casts and document the result.
4. **LDC-created-thread TLS:** perform the TLS experiment described above before
   advertising arbitrary D TLS as safe in XTB-created workers.
5. **Atomic backend widths:** enumerate the scalar widths LDC implements directly
   on each target and the subset for which the parking backend can implement
   `Atomic.wait` without hidden waiter tables.
6. **Native thread naming:** verify exact Linux limits/error mappings first; do
   not copy those limits into the portable API as constants. Windows behavior is
   validated separately when that backend is added.

If a prototype fails, prefer a narrower truthful API over an implementation that
uses hidden allocation, druntime, unsafe lifetime assumptions, or undocumented
casts.

## Implementation order

Implement in this order so each layer has a stable foundation:

1. `atomic.d` with the initial supported atomic type set, memory orders, fences,
   and non-blocking operations.
2. Architecture/platform utility foundations: `cpuRelax`, raw thread backend,
   `Thread.startRaw`/`join`/`detach`, `ThreadId`, `yieldThread`,
   `hardwareConcurrency`, current-thread naming, the stable native-start adapter,
   allocator-backed `Thread.startRawAlloc`, and allocator-backed typed
   `Thread.startAlloc`. The allocator-backed typed path deliberately comes before
   the zero-allocation typed path because stable storage removes the parking/latch
   dependency.
3. Internal parking.
4. Public `Atomic.wait`/`notifyOne`/`notifyAll` and the internal one-shot start
   latch used by typed thread startup.
5. Public `SpinWait` and typed zero-allocation
   `Thread.start!worker(args...)`.
6. `Mutex`, initially with the bounded exponential relax-then-park policy and
   checked owner/recursive-lock diagnostics.
7. `CondVar`.
8. `Semaphore`, `Once`, and `OnceCell!T`.
9. `Latch`, implemented directly on the atomic wait/notify countdown path and
   stress-tested as the first public countdown primitive.
10. Extract/refine package-private countdown and reusable generation machinery.
11. `WaitGroup` and `Barrier`, both built on the proven generation machinery but
    exposing distinct public state machines.
12. `RwLock`.
13. `spawn`, `JoinHandle!T`, and typed result storage.
14. `threadScope`, allocator-backed child tracking, scoped-borrow compiler
    prototypes, and structured join-all behavior.
15. Lock guards.
16. Monotonic time integration, sleeping utilities, and timed waits.
17. Windows backend coverage for every implemented primitive and utility.

`spawn` may be implemented immediately after typed `Thread.start` if desired;
it depends only on the raw thread layer, allocator support, and move-safe typed
storage, not on the public mutex/condition-variable primitives. `threadScope`
may similarly follow once raw/typed trampoline machinery and allocator-backed
tracking are proven, but its borrowing syntax must not be frozen before the LDC
lifetime experiments succeed.

The thread pool is a subsequent design/implementation project, not an item to
fold opportunistically into this primitive roadmap.

## Testing requirements

Ordinary unit tests are not enough for concurrency primitives. Add dedicated
stress tests, deterministic backend-injection tests, and compile-time contract
tests.

At minimum, test:

- raw start/join with null and non-null contexts;
- `startRawAlloc` allocation failure, native-start failure cleanup, child-thread
  deallocation before user worker entry, detach with a long-lived allocator, and
  allocator lifetime/thread-safety contract documentation;
- typed `startAlloc` copyable/move-only/qualified/shallow-reference captures,
  starting-thread conversion timing, exact destruction counts, `void` status
  normalization, stack options, allocation/native-start failure cleanup, and
  child-thread deallocation before user worker entry;
- compile-fail coverage for typed `ref`, `out`, `lazy`, `in`, non-static callable,
  missing `nothrow`/`@nogc`, and non-`int`/`void` worker return contracts;
- unsupported-backend start behavior, including allocator-backed starts cleaning
  their state before reporting the nested unsupported native-start error;
- native resource exhaustion/error mapping where injection is possible;
- joining exactly once;
- joining self and other lifecycle misuse through death tests;
- explicit detach for `Thread`;
- destruction of a live `Thread` through a death test;
- `currentThreadId` identity/equality behavior and post-termination non-liveness
  semantics;
- `hardwareConcurrency` returning either zero (unknown) or a positive hint;
- thread naming success plus deterministic unsupported/invalid/too-long/system
  error mapping;
- `cpuRelax` availability on every supported architecture/backend;
- `SpinWait` remaining allocation-free/BetterC-safe and eventually reaching its
  yielding phase under an instrumented policy implementation;
- typed argument count/type mismatch as compile-fail tests;
- rejection of `ref`, `out`, and `lazy` parameters for ordinary
  `Thread.start`;
- rejection of capturing delegates/nested callables with hidden context for
  ordinary starts;
- conversion into worker parameter capture types occurring before native start;
- shallow-capture lifetime tests for slices/pointers embedded in value
  arguments;
- copyable typed arguments;
- move-only typed arguments;
- typed start failure after arguments have been captured by the call;
- stack-packet lifetime under aggressive scheduling and repeated starts;
- millions of mutex-protected increments;
- mutex contention and handoff among many threads;
- deterministic/instrumented mutex slow-path tests showing fast acquire, bounded
  relax retries, and eventual park without an intermediate scheduler yield;
- mutex operation on a reported single-logical-CPU backend skipping active
  spinning;
- checked-build death tests for blocking recursive `lock`, unlock of an unlocked
  mutex, double unlock, and unlock by a non-owner;
- `tryLock` by the current owner returning false rather than deadlocking;
- release-fast representation/tests confirming checked owner metadata is absent;
- condition-variable atomic release/wait/reacquire behavior and lost-wakeup races;
- condition-variable notify-one and notify-all races;
- spurious-wakeup-safe predicate loops;
- semaphore producer/consumer stress;
- atomic wait/notify under notify-before-wait, repeated wake, and high-contention
  races;
- atomic wait returning only after observing a value different from the supplied
  old value;
- `Latch` zero-count behavior, one-shot completion, multiple waiters, concurrent
  countdown, underflow death tests, and publication ordering;
- `WaitGroup` dynamic child registration while nonzero, multiple waiters, reuse
  across many generations, count underflow death tests, and zero-to-positive
  reuse misuse death tests;
- `Barrier` repeated generations, simultaneous final arrivals,
  `arriveAndDrop`, participant reduction across generations, and completion
  ordering;
- generation-state stress that rapidly completes and reopens phases to expose
  ABA/lost-wakeup bugs;
- `Once` under high contention;
- `OnceCell!T` exactly-once initialization under contention, acquire publication,
  `tryGet` before/after initialization, move-only stored values, and exactly-once
  destruction;
- destruction/relocation misuse of a concurrently published `OnceCell` where the
  contract can be diagnosed;
- `RwLock` reader/writer exclusion and progress properties;
- `spawn` allocation failure;
- `spawnWith` propagating `ThreadStartOptions` (especially normalized stack size)
  to the native backend;
- `spawn` native start failure after successful allocation;
- spawn-state cleanup on every failure path;
- `JoinHandle!void`;
- scalar, aggregate, and move-only spawn return values;
- rejection of `ref`/borrowed spawn return types;
- exact `SpawnState` argument/result construction and destruction counts on
  every path;
- moving a `JoinHandle` across threads with a cross-thread-safe allocator;
- death/contract coverage for incompatible thread-affine allocator use where
  detectable;
- worker return type `Result!(T, E)` remaining unflattened;
- moving a `JoinHandle` before joining;
- destruction of an unjoined `JoinHandle` through a death test;
- panic from a spawned worker terminating the entire process;
- `threadScope` with zero, one, and many runtime-created children;
- scoped `ref` borrowing of enclosing stack values;
- compile-time/lifetime experiments preventing `ThreadScope` capability escape
  and obvious scoped-borrow escape patterns;
- rejection of `out`, `lazy`, and non-void workers for `scope.spawn` in v1;
- `threadScope` body compilation under `-betterC` without GC closure creation;
- all previously started scoped children still being joined when a later
  `scope.spawn` returns allocation or native-start failure;
- early normal return from the scope body still causing join-all;
- exact tracking-node allocation/deallocation counts using the same allocator;
- tracking-node cleanup always occurring on the scope-owning thread;
- scope allocator failure before native start;
- no scoped detach API as a compile-fail/API-surface check;
- atomic compare/exchange expected-value and memory-order validation; and
- focused LDC/BetterC tests for compiler TLS behavior on XTB-created threads;
- move-assignment of `Thread` and `JoinHandle` into an empty destination, plus
  death tests proving that assignment over a live destination cannot discard an
  ownership obligation;
- unsupported-backend execution of infallible blocking APIs failing explicitly
  rather than silently spinning or reporting false success;
- detached raw/typed `Thread` examples documenting and testing the lifetime
  distinction between owned captures and borrowed pointer/slice data;
- two `spawn` instantiations with the same result type but different worker
  argument/capture layouts, proving `JoinHandle!T` cleanup is genuinely
  type-erased and does not depend on the original worker type;
- heterogeneous `threadScope` children with different capture layouts in one
  intrusive child list, including exact concrete-capture destruction before
  type-erased scope cleanup;
- rejection (or the deliberately chosen explicit fallback syntax) for borrowing
  a temporary or a local whose lifetime ends with the scope-body callback before
  `threadScope` itself performs join-all;
- scoped mutable borrows being treated as a lifetime guarantee only, with race
  tests/examples demonstrating that concurrent parent/sibling access still
  requires synchronization;
- `Atomic.wait` unsupported-width/type compile-time behavior and waited-atomic
  address-stability assumptions;
- logical `size_t` counters combined with a narrower wake epoch for semaphore,
  latch, wait-group, and barrier stress, including forced/simulated wake-epoch
  wrap where the implementation exposes an injectable test policy;
- mutex contention scenarios with barging/new acquirers between a contended
  unlock and the woken waiter's retry, proving that the contended state/wake
  obligation cannot strand other parked waiters;
- condition-variable checked association with a single mutex, plus destruction
  with live waiters where diagnosable;
- semaphore `release(0)`, latch `countDown(0)`, and wait-group `add(0)`/`done(0)`
  no-op behavior, plus overflow/underflow checks in `release-fast`;
- `Barrier.init` inert behavior, `arriveAndDrop` being nonblocking, final-drop
  transition to permanent completion, and misuse after permanent completion;
- writer-preference `RwLock` tests showing that queued writers block new readers,
  while also testing the documented lack of strict FIFO/freedom from reader
  starvation under sustained writers;
- `RwLock` state-integrity misuse (unlock without matching active read/write) and
  checked writer-owner diagnostics;
- recursive `callOnce`/`OnceCell.getOrInit` checked diagnostics and proof that
  initializer arguments may be evaluated by losing callers while initializer
  function bodies execute only once;
- lock-guard move behavior, exactly-once unlock, and checked failure when an
  owning guard is illicitly transferred/destructed on a different thread; and
- compilation of every public documentation example under `-betterC` so prose
  and implementation cannot silently diverge.

Where LDC supports it reliably, provide a ThreadSanitizer test configuration for
stress suites. Sanitizer support complements but does not replace deterministic
state-machine and ownership tests.

Tests must run in checked builds and compile in `release-fast`. Semantics that
must remain safe in release builds, especially process-fatal panic,
`JoinHandle` ownership obligations, and `threadScope` join-all/lifetime behavior,
must not disappear with `XTB_Checked`. Checked-only diagnostics such as mutex
owner bookkeeping may disappear, but their removal must not change the valid
program synchronization semantics.

## Example: layered usage

Raw API:

```d
int rawWorker(void* opaque) nothrow @nogc
{
    int* value = cast(int*) opaque;
    return *value;
}

int value = 42;
Thread raw = Thread.startRaw(&rawWorker, &value).unwrap();
assert(raw.join() == 42);
```

Typed thread API:

```d
int typedWorker(int value, Config config) nothrow @nogc
{
    return value + config.bias;
}

Thread typed = Thread.start!typedWorker(42, move(config)).unwrap();
int status = typed.join();
```

Typed computation API:

```d
Result!(Config, ParseError) parseWorker(Path path) nothrow @nogc
{
    mixin ResultReturns;
    // ...
}

auto spawned = spawn!parseWorker(allocator, path);
if (!spawned)
{
    // Allocation or native thread-start failure.
    handleSpawnError(spawned.error);
    return;
}

auto handle = spawned.take();

// Other work can run concurrently here.

Result!(Config, ParseError) parsed = handle.join();
if (!parsed)
{
    // Worker/domain failure, not a threading failure.
    handleParseError(parsed.error);
    return;
}

Config config = parsed.take();
```

Structured borrowing API:

```d
void increment(ref int value) nothrow @nogc
{
    ++value;
}

int value = 41;

threadScope(allocator, (ref scope) {
    scope.spawn!increment(value).unwrap();
    scope.spawn!doOtherBorrowedWork(...).unwrap();
}); // all children joined, tracking nodes freed with allocator

assert(value == 42);
```

The examples intentionally expose progressively stronger ownership and typing
guarantees while preserving access to the raw primitive underneath. Structured
scopes add lexical borrowing and guaranteed join-all rather than another
individually owned thread handle.
