# Threading implementation status

This file tracks implementation of `design_spec/threading.md`.

The order is deliberate: features with no `xtb_threading` prerequisites come
first, then dependent features are ordered by foundational importance and the
implementation order in the threading specification. A feature is marked
complete only after its focused tests pass under BetterC and the relevant
repository-wide test/build checks have been attempted.

Status values:

- **complete**: implemented and tested for the currently supported backend;
- **next**: highest-priority feature whose prerequisites are complete;
- **pending**: not yet implemented;
- **blocked**: waiting on a prerequisite or prototype/design gate.

## Feature order

| # | Status | Feature | Depends on | Notes |
|---|---|---|---|---|
| 1 | **complete** | Non-blocking atomics and memory model | — | `MemoryOrder`, scalar `Atomic!T`, `AtomicFlag`, load/store/exchange/CAS, integral fetch operations, and `atomicThreadFence`. Atomic wait/notify is intentionally separate. |
| 2 | **complete** | Raw thread/platform foundations + allocator-backed starts | 1 for the POSIX ABI handoff; typed `startAlloc` also uses core allocator/lifetime support | `cpuRelax`, `Thread.startRaw`/`startRawWith`, `startRawAlloc`/`startRawAllocWith`, typed `startAlloc`/`startAllocWith`, lifecycle, join/detach, `ThreadId`, start options/errors, stable native-start adapter, `currentThreadId`, `yieldThread`, `hardwareConcurrency`, Linux naming, and an explicit unsupported backend. |
| 3 | **complete** | Internal parking | 1 | Package-private 32-bit compare-and-sleep parking with Linux process-private futex wait/wake and explicit unsupported-platform failure. |
| 4 | **complete** | Atomic wait/notify and startup latch | 1, 3 | Public `Atomic.wait`/`notifyOne`/`notifyAll` plus the allocation-free internal one-shot start latch are complete. |
| 5 | **complete** | Typed zero-allocation `Thread.start` | 2, 4 | `start`/`startWith` use worker-typed parent-stack captures and a one-shot latch handoff; the worker runs only after capture ownership has moved to child-local storage. |
| 6 | **complete** | `SpinWait` | 2 | Bounded exponential processor relaxation followed by scheduler yield. |
| 7 | **complete** | `Mutex` | 1, 2, 3, 6 | Fast acquire, bounded relax-then-park slow path, checked owner diagnostics. |
| 8 | **complete** | `CondVar` | 3, 7 | Stack-backed waiter queue, exact notify-one/all selection, and explicit waiter-node lifetime handshake. |
| 9 | **complete** | `Semaphore` | 1, 3, 4 | Atomic fast permit path plus intrusive stack-waiter handoff; no shared wrapping wake epoch. |
| 10 | **complete** | `Once` | 1, 3, 4 | Exactly-once execution with publication and recursive-use diagnostics. |
| 11 | **complete** | `OnceCell!T` | 10 | Allocation-free typed one-time initialization and exact manual lifetime handling. |
| 12 | **complete** | `Latch` | 1, 3, 4 | One-shot countdown with a full-width logical count and a 32-bit wait epoch. Implemented early while auditing the decided countdown design. |
| 13 | **complete** | Internal generation machinery | 12 | `GenerationWaitState` uses one 32-bit phase token for identity and parking, plus checked-build waiter tracking. |
| 14 | **complete** | `WaitGroup` | 13 | Dynamic registration, reuse across generations, underflow/reuse misuse checks. |
| 15 | **complete** | `Barrier` | 13 | Reusable generations, arrival/drop semantics, permanent completion. |
| 16 | **next** | `RwLock` | 1, 3 | Writer-preference reader/writer lock and checked writer-owner diagnostics. |
| 17 | pending | `spawn` and `JoinHandle!T` | 2 | Explicit allocator-backed typed result transport and move-only join ownership. |
| 18 | pending | `threadScope` | 2, 17 | Allocator-backed heterogeneous child tracking, scoped borrowing, guaranteed join-all. |
| 19 | pending | Lock guards | 7, 16 | `LockGuard`, `ReadLockGuard`, and `WriteLockGuard` with move-only lexical ownership. |
| 20 | blocked | Monotonic time, sleeping, and timed waits | time foundation | Requires a stable monotonic-time abstraction that preserves the threading package dependency direction. |
| 21 | pending | Windows backend coverage | public contracts above | Implement every completed OS-dependent primitive/utility with the same public semantics. |

## Feature 1 completion record

Implemented `xtb.threading.atomic` with the five-order C/C++-style memory model,
non-copyable scalar `Atomic!T`, `AtomicFlag`, load/store/exchange, weak and strong
compare/exchange, integral fetch operations, and `atomicThreadFence`. Blocking
atomic wait/notify is intentionally deferred until the parking backend exists.

Validation performed with the supplied LDC 1.42.0 toolchain:

- compile-time acceptance/rejection checks for the supported scalar, enum,
  pointer, qualified, aggregate, and copyability boundaries;
- all valid compare/exchange success/failure-order classes plus expected-value
  replacement on failure;
- invalid-order death tests, including release/acquire misuse and invalid enum
  values, executed in checked builds and manually in release-fast;
- eight-thread relaxed `fetchAdd` stress (800,000 total increments per run);
- release/acquire publication between independent POSIX threads;
- package aggregate-import coverage through `import xtb.threading;`;
- debug, optimized, release-safe, release-fast compile, release-fast runtime,
  and AddressSanitizer runs;
- independent component builds in debug, release-safe, and release-nobounds;
- syntax-only BetterC build with `XTB_Checked`;
- `dfmt --config .` format checks and D-Scanner 0.15.2 style/lint checks for
  all Feature 1 D files; and
- undefined-symbol inspection of `libxtb_threading.a`, confirming no
  `__atomic*`, pthread, D runtime metadata, or TypeInfo/ModuleInfo dependency in
  the atomic component.

LDC's `core.atomic.atomicExchange` rejects acquire-only exchange in this
frontend, despite acquire being valid for a C/C++ read-modify-write operation.
The implementation therefore builds exchange from the compiler CAS primitive;
no architecture-specific assembly or hidden lock table is used.


## Feature 2 completion record

Implemented the raw native-thread/platform foundation with a Linux pthread
backend and an explicit unsupported backend. The public surface now includes
`Thread.startRaw`/`startRawWith`, allocator-backed `startRawAlloc`/
`startRawAllocWith`, typed allocator-backed `startAlloc`/`startAllocWith`,
`ThreadStartOptions`, `ThreadStartError`, `ThreadStartAllocError`, move-only
`Thread` ownership, `ThreadId`, join/detach, thread naming, `currentThreadId`,
`yieldThread`, `hardwareConcurrency`, and `cpuRelax`.

The Linux backend now has two deliberate native-entry adapters. The
allocation-free raw callback bridge preserves the portable `int function(void*)`
contract with a small parent-stack packet: the child copies the runtime function
pointer and user context, signals the package-private one-shot `StartLatch`, and
only then calls user code; the parent waits on that latch before returning. The
latch supplies the release/acquire publication edge and parks rather than
repeatedly yielding when the child is not scheduled promptly. It waits only for
ABI packet capture, never for worker execution. Linux architectures without an
implemented parking backend retain the original bounded-relax/`sched_yield`
bootstrap fallback so raw thread creation does not acquire a new parking
prerequisite.

The second adapter accepts already-stable start storage. `startRawAlloc` uses one
caller-allocator allocation for the raw function/context adapter, while typed
`startAlloc` uses one allocation containing the backend adapter plus captures in
the worker's declared parameter types. The allocator callback type now lives in
the allocator contract in `xtb.core.memory`; concrete allocator implementations
remain isolated under `xtb.core.allocators.*`, so threading can use the public
allocator API without importing a concrete allocator implementation. After
successful native creation the child moves/copies every value it needs into
child-stack call storage, destroys
all source captures, deallocates the start state on the child thread, and only
then enters user code. These allocating forms therefore return after native
creation without a child-start rendezvous. The allocator must remain valid until
that child-side release and must allow deallocation from the child thread;
short-lived arena/scratch/thread-affine allocators are invalid unless their own
lifetime and cross-thread contracts explicitly satisfy those requirements.

Validation performed with the supplied LDC 1.42.0 toolchain includes:

- null and non-null raw contexts plus exact signed `int` status transport,
  including `int.min` and `int.max`;
- 1,024 batched raw start/join operations and explicit detach completion;
- move construction, move assignment into an empty destination, and
  unconditional death coverage for assignment over a live destination;
- compile-time safety-boundary checks proving ordinary handle lifecycle and
  utility operations are callable from `@safe` code through narrow trusted
  wrappers while the raw `void*` start surface remains `@system`;
- death tests for null entry, empty/double join and detach, empty `id`/naming,
  self-join, destruction of a joinable owner, and process-fatal worker panic;
- `ThreadId` agreement between parent handle and child `currentThreadId`,
  distinction from the parent thread, and stable identity after worker
  publication while the handle remains joinable;
- default, tiny, explicit non-page-sized, and overflowing stack requests,
  including native observation that normalized stack size never falls below the
  requested minimum;
- Linux current-thread and handle naming, exact 15-byte Linux name acceptance,
  too-long and embedded-NUL errors, and the exited-but-unjoined
  `threadUnavailable` race;
- affinity-aware `hardwareConcurrency`, scheduler yield, and x86_64 assembly
  inspection confirming `cpuRelax` emits `pause` rather than a scheduler yield;
- direct LDC TLS probing from an XTB-created pthread, confirming independent
  zero-initialized module TLS on this supported target;
- deterministic internal errno mapping checks for `EAGAIN`/`ENOMEM` resource
  exhaustion, `EPERM` permission failure, and `EINVAL` invalid configuration;
- allocator-backed raw start proving exactly one allocation, child-thread
  deallocation before user worker entry, signed status transport, and safe detach
  with the long-lived malloc allocator;
- allocator-backed typed start covering multiple/value/`const`/slice and
  over-aligned captures, `void` status normalization, move-only capture with
  exactly-once destruction,
  parent-thread conversion into worker parameter types, explicit stack options,
  allocation failure, native-start failure cleanup, and child-thread deallocation
  before user worker entry;
- compile-time rejection of typed `ref`, `out`, `lazy`, `in`, top-level `shared`,
  non-static member and nested/capturing callables, argument-count mismatch,
  missing `nothrow`/`@nogc`, `ref` returns, and non-`int`/`void` value returns,
  plus acceptance of static member workers;
- forced unsupported-backend runtime tests with no pthread backend linked,
  including one-allocation cleanup for both raw and typed allocator-backed starts;
- successful x86_64 Windows cross-compilation of `import xtb.threading` with raw
  and typed allocator-backed starts instantiated, proving the unsupported backend
  and allocator type dependency remain import/compile portable for that target;
- focused D-Scanner/dfmt checks plus debug, optimized, release-safe,
  release-fast, and AddressSanitizer threading test runs; and
- static-library symbol inspection confirming no malloc/calloc/realloc/free,
  `__atomic*`, TypeInfo/ModuleInfo, or D GC/runtime dependency is introduced by
  the raw threading implementation. Native pthread/scheduler/sysconf symbols are
  the expected Linux backend boundary.

LDC's bundled FreeBSD headers reject the generic cross target before XTB code is
semantically checked (`core.sys.freebsd.config` reports an unsupported FreeBSD
version), so Windows is the exercised unsupported-platform cross-compile target
for this completion record.


## Feature 3 completion record

Implemented `xtb.threading.internal.parking` as the package-private blocking
foundation for later atomic wait/notify and synchronization primitives. The v1
wait word is exactly 32 bits. `park(address, expected)` uses the Linux futex
compare-and-sleep operation, so a value change that races with the transition
into the kernel produces `ParkResult.valueMismatch` instead of sleeping on a
stale observation. Successful wakes, `EINTR`, and other permitted spurious
returns are represented as `ParkResult.wokenOrSpurious`; higher-level protocols
remain responsible for looping and re-checking their atomic state.

Linux uses `FUTEX_WAIT_PRIVATE`/`FUTEX_WAKE_PRIVATE`, deliberately limiting the
v1 parking contract to synchronization between threads in one process. Wake
operations carry no memory ordering themselves; publication belongs to the
atomic state transition performed by the caller. Unexpected futex errors are
fatal internal/programming failures rather than new recoverable API states. An
unsupported parking backend also fails explicitly through `panic` rather than
spinning or pretending to block.

D toolchains are not consistent about exposing the libc `syscall` declaration
through `core.sys.linux.unistd`, and the headers also need not expose `SYS_futex`.
The Linux parking module therefore declares the libc `syscall` ABI directly and
contains the stable Linux futex syscall-number mapping for target architectures
it recognizes; unknown architectures still compile with an explicit
unsupported-architecture panic path. Runtime validation for this feature is on
x86_64 Linux.

Validation includes:

- deterministic `EAGAIN` -> `valueMismatch` and `EINTR` ->
  `wokenOrSpurious` result classification;
- direct mismatch without sleeping;
- a gated wake-before-park race proving the kernel compare-and-sleep check
  closes the lost-wakeup window;
- wake-one against a live waiter without changing the wait word;
- eight concurrent waiters across 64 repeated generations using wake-all, with
  bounded progress checks around every generation;
- forced-unsupported death tests for `park`, `wakeOne`, and `wakeAll`;
- debug, optimized, release-safe, release-fast, and AddressSanitizer threading
  runs;
- dfmt and D-Scanner checks for the new/modified files; and
- unsupported-target compile checks ensuring Linux-only syscall imports do not
  leak into non-Linux builds.

## Feature 4 completion record — atomic wait/notification and startup latch

Implemented public blocking wait/notification on `Atomic!T` using the Feature 3
parking backend. `Atomic!T.waitSupported` is a compile-time property of each
atomic instantiation. For the current Linux futex backend it is true only for
32-bit supported atomic scalar types on architectures for which the parking
backend has a known futex syscall mapping. Unsupported widths and unsupported
parking backends retain the existing non-blocking atomic operations but do not
expose `wait`, `notifyOne`, or `notifyAll`.

`wait(oldValue, order)` validates that the load order is `relaxed`, `acquire`,
or `sequentiallyConsistent`, repeatedly performs an atomic load, and parks only
while the full atomic value still equals `oldValue`. Every return from the
parking backend is followed by another atomic comparison, so notifications that
do not change the value, `EINTR`, and other permitted spurious wakes cannot
cause the public wait operation to return early. `notifyOne` and `notifyAll`
carry no independent publication ordering; callers publish state with the
atomic store/RMW that precedes notification.

Validation for this commit includes:

- compile-time wait-support checks for 16-, 32-, and 64-bit atomic widths,
  32-bit enum values, shared receivers, and the forced-unsupported backend;
- immediate-return checks for all three valid wait memory orders;
- release/acquire publication through the wait path;
- repeated notification without a state change, stress-checking that public `wait`
  rechecks the value instead of exposing a notification/backend wake;
- 2,048 generation transitions using `notifyOne`, deliberately allowing each
  notification to race with the next entry into `wait` and thereby stressing
  the wake-before-park/lost-wakeup boundary;
- eight concurrent waiters released through `notifyAll`;
- a signed 32-bit waited value (`-1`) to exercise exact futex expected-word
  conversion;
- unconditional death tests for `release`, `acquireRelease`, and an invalid
  `MemoryOrder` value passed to `wait`;
- debug, optimized, release-safe, release-fast, and AddressSanitizer focused
  threading runs; and
- Linux cross-compilation of wait/notify probes for i686, ARM, AArch64,
  RISC-V64, PPC64LE, s390x, and LoongArch64, including the 32-bit pointer-wait
  path where applicable; and
- x86_64 Windows/MSVC cross-compilation proving the unsupported parking backend
  reports `waitSupported == false` without leaking Linux futex imports.

The second Feature 4 commit adds package-private `StartLatch` on top of that
atomic wait/notification path. `StartLatch.init` represents the pending state; it
is non-copyable, contains exactly one 32-bit atomic state word, allocates nothing, has no reset
operation, and uses a release store plus `notifyOne` on `signal` paired with an
acquire `wait`. This matches the thread-start ownership-transfer protocol: once
the signaling child publishes completion, the waiting starter may safely destroy
the stack-backed packet.

Latch validation includes signal-before-wait, wait-before-signal, release/acquire
publication, 1,024 independent one-shot handoffs, copy rejection, exact
size/alignment checks, and forced-unsupported death behavior. Migration of the
existing raw-thread bootstrap handoff to `StartLatch` is performed in the
following refactoring commit so the latch commit itself contains only the
primitive and its tests.

## Raw-start latch integration record

The Linux allocation-free raw start adapter now uses `StartLatch` for its
parent-stack ownership handoff whenever the parking backend is supported. The
child copies the function/context, signals the latch as its final packet access,
and only then invokes user code; the parent waits only for that signal. This
removes the host Linux raw-start spin/yield polling loop without changing the
public API or the allocator-backed `startRawAlloc`/`startAlloc` paths.

For Linux architectures where the parking backend is not implemented, the
existing bounded relax-then-yield bootstrap remains compiled as a fallback.
This preserves Feature 2 raw-thread availability instead of making thread
creation itself depend on parking support.

Integration validation includes the existing 1,024 raw start/join stress run,
a dedicated test proving `startRaw` returns after adapter capture but before a
blocked user worker completes, ten repeated debug stress-suite executions,
optimized/release-safe/release-fast and AddressSanitizer runs, direct execution
of the no-parking fallback, host symbol inspection proving the supported path
references `StartLatch.wait`/`signal` rather than the old polling atomics, and
Linux cross-compilation for every architecture with a v1 futex mapping.

## Feature 5 completion record — typed zero-allocation thread start

Implemented `Thread.start!worker(args...)` and `Thread.startWith!worker(options,
args...)` as the allocation-free typed start surface. Argument conversion into the
worker's declared parameter types occurs synchronously in the starting thread.
Those captures live in a parent-stack packet until the child moves them into
child-local values, destroys the source captures, and signals `StartLatch` as its
final packet access. Only then may the parent return and let the packet disappear;
the user worker is invoked after the signal, so worker duration does not extend
the start call.

The stack-backed and allocator-backed typed paths reuse the same generated
`TypedCaptures` storage and exact-destruction helper. Their trampolines remain
separate because their ownership completions differ deliberately: stack-backed
start signals the parent latch, while allocator-backed start deallocates stable
state on the child thread. Callable validation and worker argument rules are
shared unchanged between both surfaces.

Validation includes zero-argument, `int`, and `void` workers; `const`, slice, and
over-aligned captures; move-only exact destruction; parent-thread conversion
into the declared worker parameter type; explicit stack options; native-start
failure cleanup; a blocked worker proving typed start returns after capture
handoff rather than worker completion; a short 32-start handoff stress run; and
compile-time acceptance/rejection checks matching the allocator-backed typed
surface. Forced-unsupported tests verify `Thread.start` returns
`ThreadStartErrorKind.unsupported` rather than attempting to use an unavailable
start latch.

## Prototype gates

| Gate | Status | Required before | Result / notes |
|---|---|---|---|
| Atomic backend widths / direct operations | **complete for LDC 1.42.0 x86_64 Linux** | Feature 1 | Probed 1/2/4/8-byte integral and enum values plus native pointers; LDC emitted native atomic instructions with no unresolved `__atomic*` runtime calls in the probe. Feature 4 additionally restricts blocking wait/notify to 32-bit scalar atomics on a parking-supported backend through `Atomic!T.waitSupported`. |
| Atomic/shared receiver behavior | **complete for Feature 1** | Feature 1 | D requires distinct shared and unshared receiver overloads. `Atomic!T`/`AtomicFlag` expose both, with qualifier casts contained inside trusted atomic boundaries. |
| Static memory-order diagnostics | **documented language/API limitation** | Feature 1 | The specified public syntax passes `MemoryOrder` as a runtime value. D semantic analysis does not preserve whether that argument originated from an enum literal, so the implementation cannot reject a literal invalid order at compile time without changing the call syntax to template value parameters. All invalid orders/combinations are still unconditional programming-error panics. |
| Parameter storage-class introspection | **complete for typed starts** | Feature 2 allocator-backed typed start / Feature 5 zero-allocation typed start | LDC 1.42.0 reports `ref`/`out`/`lazy` explicitly; `scope`/`return` can decorate value transport. A focused address probe showed `in` is value-like under the repository flags but aliases caller storage under `-preview=in`, so v1 typed starts reject `in` in all modes. |
| LDC-created-thread TLS | **complete for LDC 1.42.0 x86_64 Linux** | Raw/typed thread TLS guarantees | A raw XTB pthread sees module TLS at its independent zero-initialized value and writes do not affect the parent thread TLS instance. This validates compiler TLS for the supported Linux target; it is not a promise for untested compiler/platform combinations. |
| Native thread naming limits/error mapping | **complete for Linux** | Feature 2 naming freeze | Linux `pthread_setname_np` behavior was tested: 15 UTF-8 bytes are accepted, 16 are `tooLong`, embedded NUL is `invalidName`, and an exited-but-unjoined pthread maps to `threadUnavailable`. The Linux byte limit remains private. |
| Scoped structured-borrow syntax | pending | Feature 18 | Prove BetterC/no-GC closure behavior and non-escape properties or use the explicit context fallback. |
| Broader `shared`/`inout` policy | pending | Cross-primitive API freeze | Feature 1 records only the atomic-specific result; mutex-protected object graphs and typed worker arguments still need focused experiments. |

## Repository cleanup status

The stale `Option.set` call sites that were present in the supplied snapshot have
been migrated to the current explicit `some(...)` assignment API in `xtb.os`,
serde tests, and the serde example. The OS and serde debug runners now compile
and pass alongside the other test targets.

The repository-wide D-Scanner 0.15.2 policy pass is clean for every file that
version can analyze reliably. The compatibility exclusions in `dscanner.ini`
cover the print/pretty-print interpolation-sequence files plus logging and
stacktrace-style files that this scanner version either cannot parse or does not
terminate on; LDC continues to compile-check all excluded files. The real
style/static-analysis findings previously reported in core `result.d`, the
intrusive-list layout assertions, parser, and TOML have been fixed.

The repository-wide dfmt cleanup has been applied. Interpolation-expression
sequence files were tested separately before inclusion; dfmt preserved the
interpolation expressions and their focused compiler/runtime tests remained
clean.

## SpinWait completion record

Implemented public `SpinWait` in `xtb.threading.spin_wait`. `SpinWait.init` is
round zero. Successive `spin()` calls use bounded exponential `cpuRelax()`
batches of 1, 2, 4, 8, 16, 32, and 64 hints; after that the internal round
counter saturates and each later `spin()` calls `yieldThread()` until `reset()`
returns it to round zero. The helper never parks and provides no memory ordering.

The implementation keeps the backoff schedule in one small private helper so the
production path and deterministic unit test exercise the same state machine. The
test policy counts relax/yield actions without sleeping or creating threads,
verifying the exact initial v1 sequence, transition to yielding, saturation, and
reset behavior while keeping the normal test suite fast.

## Mutex completion record

Implemented public allocation-free `Mutex` with zero-valid unlocked state,
non-copyable value semantics, and the v1 three-state atomic protocol: `0` is
unlocked, `1` is locked without known contention, and `2` is locked/contended.
The fast path acquires with CAS `0 -> 1`. The slow path performs bounded
1/2/4/8/16/32/64 `cpuRelax()` batches with acquisition retries, preserves a
locally observed contended state, then uses the atomic wait/notification parking
path. It deliberately never scheduler-yields between active spinning and
parking. Unlock exchanges the state to zero with release ordering and wakes one
waiter when the previous state was contended.

In `XTB_Checked` builds Mutex also carries an atomic owner identity used only for
diagnostics. Blocking recursive lock, unlock of an unlocked mutex, double
unlock, unlock by a non-owner, and destruction while locked are diagnosed as
programming errors. `tryLock()` remains a non-blocking probe and returns `false`
when the current thread already owns the mutex. The owner field is compiled out
outside `XTB_Checked`; the release representation is only the 32-bit atomic
state word.

Validation covers basic lock/tryLock/unlock behavior, deterministic verification
of the bounded 127 total relax hints, a short four-thread protected increment
run, contended handoff with release/acquire publication, and checked-build death
tests for the ownership/lifecycle diagnostics. The tests intentionally use
small iteration counts so ordinary threading test runtime remains short.

## CondVar completion record

Implemented public allocation-free `CondVar` in `xtb.threading.cond_var` with
`wait(ref Mutex)`, `notifyOne`, and `notifyAll`. The final implementation does
not use the earlier wrapping sequence or two reusable group-slot designs. Each
`wait` owns a private stack-backed waiter record containing one wait-supported
32-bit atomic and one `ForwardListHook`. `CondVar` itself owns a private `Mutex`
plus XTB core's allocation-free `IntrusiveQueue`; there is no hidden allocator,
waiter table, native condition-variable object, notification generation, or
finite-width reuse counter. The intrusive queue centralizes the ordinary FIFO
head/tail invariants and contributes only checked-build membership diagnostics
beyond the single forward link required by the waiter.

A waiter enqueues while it still owns the predicate mutex and while the private
CondVar mutex is held. The private mutex remains held across the predicate-mutex
release, making registration/release one serialized wait commit. `notifyOne`
removes one waiter (FIFO internally), stores its private signal word to one, and
wakes that exact address. `notifyAll` drains the current `IntrusiveQueue` while
holding the private mutex and signals/wakes every node in that serialized
population; later registrations cannot enter the queue until the broadcast
releases the mutex.

The stack-pointer lifetime rule is explicit. A notifier retains the private
CondVar mutex through its final waiter-node access, including the wake call.
After notification, the waiter reacquires the predicate mutex and then
acquires/releases the private CondVar mutex before returning, proving that no
notifier can still hold a live pointer to its stack node. This removes both the
32-bit generation ABA problem and the progress problem found in the abandoned
quiescent-slot prototype: notification never waits for a descheduled waiter to
release a slot-reuse reference. The deliberate tradeoff is that `notifyAll`
performs one parking-backend wake per registered waiter rather than a shared
single-word broadcast.

Validation covers one-waiter publication/reacquisition, multiple waiters with a
single logical `notifyOne`, multi-waiter `notifyAll`, deterministic
registration-before-park notification, deterministic notifier/waiter node
lifetime synchronization, repeated bounded wait/notify cycles including
notification while holding the predicate mutex, checked misuse for waiting
without mutex ownership and mixing predicate mutexes, forced
unsupported-backend behavior, cross-compilation of the threading component,
and the normal optimized, release-safe, release-fast, sanitizer, formatting,
and lint passes. No test depends on FIFO completion order.

## Semaphore completion record

Implemented public allocation-free `Semaphore` in `xtb.threading.semaphore`.
`Semaphore.init` has zero permits and `Semaphore(n)` supports an explicit initial
count. The fast state is an `Atomic!size_t` count of available, unreserved
permits. `tryAcquire` is a true non-blocking CAS-decrement path: it does not take
the semaphore's private mutex and cannot park. Immediate `acquire` uses that same
path.

A blocking acquire uses a stack-backed `SemaphoreWaiter` containing one 32-bit
one-shot state word and one `ForwardListHook`, registered in XTB core's
`IntrusiveQueue` under a private `Mutex`. The slow path rechecks the atomic permit
count while registration is serialized, closing the release-before-registration
race. The invariant is that a non-empty waiter queue implies zero unreserved
permits. `release(n)` therefore hands its first permits directly to queued waiters
and publishes only the remainder into the atomic count, preventing fast-path
barging from stealing a permit already selected for a waiter.

The waiter word has `queued`, `parking`, and `signaled` states. If release wins
before the waiter commits to parking, the waiter observes `signaled` and no futex
wake syscall is necessary. If the waiter has committed to parking, release wakes
that private address after publishing `signaled`. Every blocking call owns a
unique wait word, so the discarded shared `wakeEpoch` design's finite-width
wrap/ABA problem does not exist. Release/acquire ordering is carried by the
atomic permit CAS for stored permits and by the waiter-state release/acquire pair
for direct handoffs.

Releasers keep the private mutex through their final access to a stack waiter,
including any wake. A signaled acquire crosses that mutex before returning,
proving the waiter node cannot leave scope while another thread can still touch
it. This is the same lifetime principle used by `CondVar`, without reusable
parking-slot reclamation or waiting for a descheduled waiter. Overflow of the
`size_t` unreserved-permit count is an unconditional fatal programming error.
On unsupported parking backends, `release`, `tryAcquire`, and an immediately
successful `acquire` remain functional; only an acquire that actually needs to
block panics explicitly.

Validation covers zero/nonzero initial counts, release-zero, exact multi-permit
release, a deliberately locked internal mutex proving `tryAcquire` stays
non-blocking, separate stored-permit and direct-handoff publication tests,
deterministic registration-before-park release, deterministic stack-node lifetime
synchronization, repeated four-thread contention with capacity two, permit
conservation, `size_t.max` overflow death, and forced unsupported-backend
behavior. The threading suite passes checked debug, optimized, release-safe, and
AddressSanitizer runs; the unchecked release-fast threading component compiles;
and the standalone BetterC semaphore module cross-compiles for i686 Linux,
AArch64 Linux, RISC-V64 Linux, and x86-64 Windows.

## Once completion record

Implemented public allocation-free `Once` and `callOnce` in
`xtb.threading.once`. The zero-valid state uses the specified uninitialized,
initializing, and initialized atomic states. One caller wins the `0 -> 1` CAS,
runs the selected context-free initializer synchronously, then publishes state
2 with release ordering and wakes all waiters. Losing callers wait on the same
32-bit state and return through an acquire observation of completion.

Initializers must be module-level or static `nothrow @nogc` functions returning
`void`. Their parameters use the same explicit by-value transport policy as
ordinary typed thread starts: `ref`, `out`, `lazy`, and preview-sensitive `in`
are rejected. Argument expressions are still evaluated for every caller before
winner selection, while the initializer body runs exactly once. Checked builds
record the initializing thread and reject recursive `callOnce` on the same
object; that owner field is absent from release-fast representation.

Validation covers sequential exactly-once behavior, argument evaluation by a
losing caller, compile-time callable/return/parameter rejection, eight-way
contention with release/acquire publication, checked recursive-use death, and
the non-copyable/release-representation contracts.

## OnceCell completion record

Implemented public allocation-free `OnceCell!T` in
`xtb.threading.once_cell`. Each cell contains the completed `Once` state machine
and union-backed raw storage for one `T`. The winning caller constructs the
initializer result directly into that storage before `Once` publishes
completion; `isInitialized`, `tryGet`, and every returning `getOrInit` call
observe publication with acquire ordering. The aggregate threading module
re-exports the new API.

Initializers follow the context-free module/static `nothrow @nogc` policy and
use ordinary by-value arguments. They must return an owned value constructible
as `T`; `void` and borrowed `ref` returns plus `ref`, `out`, `lazy`, and `in`
parameters are rejected. Move-only results are supported without adding a copy
requirement. The cell suppresses automatic destruction of its raw slot and
destroys `T` exactly once only after successful initialization.

Validation covers empty and initialized nonblocking queries, stable mutable and
const borrowed pointers, argument evaluation by losing callers, sequential and
eight-way contended exactly-once initialization, release/acquire publication,
move-only storage and exact destruction, compile-time callable rejection,
checked recursive initialization, checked destruction during active
initialization, non-copyability, and uncontended operation on the forced
unsupported parking backend. The explicit BetterC runners now enumerate the
`Latch`, `Once`, and `OnceCell` colocated tests on both backend configurations.
Focused and repository-wide validation passes in checked debug, optimized,
release-safe, and AddressSanitizer modes; release-fast production and test
targets compile without checked metadata; every example runs; the public cell
surface cross-compiles for x86-64 Windows; and the release threading archive
introduces no allocator, TypeInfo, ModuleInfo, or D runtime dependency.

## Latch completion record

Implemented public allocation-free `Latch` over the package-private
`CountdownState`. The logical count is an `Atomic!size_t`, while blocking uses
a separate wait-supported 32-bit wake epoch. This keeps the full public
`size_t` range without assuming that the native parking backend can wait on a
machine-width count. `Latch.init` is complete, `countDown(0)` is a no-op, and a
CAS loop rejects underflow before changing the count. The single zero
transition advances the epoch and wakes all waiters.

Release/acquire ordering publishes writes performed before every contributing
countdown to waiters that observe completion. On an unsupported parking backend,
zero-state operations and nonblocking queries remain functional; only a wait on
an incomplete latch fails explicitly. The type is non-copyable and follows the
package-wide address-stability rule once published.

Validation covers the zero state, partial and batched countdown, zero-count
no-op behavior, multi-waiter completion and publication, concurrent countdown
publication, full join cleanup, and unconditional underflow death behavior.
The aggregate module re-exports `Latch`, and both the native and forced-
unsupported BetterC threading runners enumerate its module and internal state.

## Internal generation machinery completion record

Implemented package-private `GenerationWaitState` in
`xtb.threading.internal.generation_wait` as the reusable phase-change waiting
foundation for `WaitGroup` and `Barrier`. One wait-supported 32-bit atomic is
both the phase identifier and the parking word. Completion increments it with
release ordering and wakes all waiters; atomic compare-and-sleep prevents a
completion between observation and parking from becoming a lost wakeup.

This modulo-width token is sufficient because `WaitGroup` forbids opening the
next generation until old waiters return, while a `Barrier` waiter necessarily
spans only its current phase. A valid waiter therefore cannot remain associated
with one value through 2^32 completions. Checked builds additionally register
active waiters with overflow/underflow protection, expose a package-level reuse
query, and diagnose destruction while a waiter remains registered; this
metadata is absent from release-fast builds.

Validation covers zero-state and immediate changed-generation behavior,
eight-waiter wake-all publication, exact waiter registration/cleanup, 2,048
rapid reusable generations with deliberate completion-before-park races, forced
32-bit generation wrap, non-copyability, and nonblocking operation on the forced
unsupported backend. Both explicit BetterC threading runners enumerate the new
internal module. Focused and repository-wide validation passes in checked debug,
optimized, release-safe, and AddressSanitizer modes; release-fast production and
test targets compile; every example runs; the module cross-compiles for x86-64
Windows; and the release threading archive adds no allocator, TypeInfo,
ModuleInfo, or D runtime dependency.

## WaitGroup completion record

Implemented public allocation-free `WaitGroup` with a full-width atomic
outstanding count and the shared 32-bit `GenerationWaitState`. A private mutex
serializes count-changing operations and waiter registration so that the final
`done` publishes zero and advances the generation as one semantic transition;
a zero-to-positive `add` cannot open a new generation between those actions.
The atomic count keeps `tryWait` nonblocking, while positive-count `wait` calls
snapshot and park on the generation token without holding the mutex.

Positive adds while work remains join the current generation, enabling dynamic
child registration. Zero-count adds and completions are no-ops. Overflow and
underflow are unconditional fatal programming errors. Checked builds retain
waiter registration through the post-wake return gate, diagnose premature
zero-to-positive reuse and destruction with outstanding work, and remove that
diagnostic bookkeeping from release-fast builds. Final completion uses
release/acquire ordering and the mutex's release chain so every contributing
worker write is visible to returning waiters.

Validation covers the zero state, no-op operations, the complete `size_t`
range, batched completion, concurrent dynamic registration, eight completing
workers, four waiters, publication, 512 immediate reuse generations, and full
thread cleanup. Death tests cover unconditional count overflow/underflow plus
checked premature reuse and active destruction. The forced unsupported backend
keeps uncontended and nonblocking operations usable while a positive-count
wait fails explicitly. The aggregate module re-exports `WaitGroup`, and both
BetterC threading runners enumerate its colocated tests.

Repository-wide lint and debug, optimized, release-safe, release-fast compile
and manual runtime, and AddressSanitizer test modes pass with LDC 1.41.0. The
threading component
builds in all three production modes, every example runs, the public module
cross-compiles for x86-64 Windows, and the release threading archive adds no
allocator, TypeInfo, ModuleInfo, or D runtime dependency. Focused formatting
passes; the repository-wide format check remains blocked only by the existing
format mismatch in `source/xtb/threading/internal/thread_linux.d`, which this
feature does not modify.

## Barrier completion record

Implemented public allocation-free `Barrier` with full-width `size_t` current
and next-generation counts plus the shared 32-bit `GenerationWaitState`. A
private mutex makes arrival, permanent drop, phase reset, and generation
advance linearizable. Non-final `arriveAndWait` callers register before
releasing the state mutex and park without holding it; the final arrival resets
the next phase, advances the generation with release ordering, and wakes every
waiter. The mutex handoff chain and generation acquire establish publication
for writes contributed by every participant.

`Barrier.init` is a valid inert state whose arrival operations fail explicitly.
The explicit constructor accepts the complete positive `size_t` range and
rejects zero in every build. `arriveAndDrop` contributes the caller's current
arrival, reduces all later phase counts, and never waits for phase completion.
The final drop advances the current generation before entering the permanent
zero-participant state; both arrival operations reject subsequent use. The type
is non-copyable and retains checked active-waiter diagnostics through the shared
generation state.

Validation covers a one-participant fast path, eight participants crossing 512
phases, simultaneous arrivals, release/acquire publication, staged participant
reduction from four to zero, an early nonblocking drop, and a final drop that
publishes data while waking a parked waiter. Unconditional death tests cover a
zero constructor, both arrival operations on `Barrier.init`, and both arrival
operations after permanent completion. The forced unsupported backend supports
single-participant phase completion and all-drop completion while a genuinely
blocking arrival fails explicitly. Both BetterC threading runners enumerate the
module, and the aggregate package re-exports it.

Repository-wide lint and debug, optimized, release-safe, release-fast compile
and manual runtime, and AddressSanitizer test modes pass with LDC 1.41.0. The
monolithic and component libraries build in every production mode, all examples
run, checked and unchecked public modules cross-compile for x86-64 Windows, and
the release archive adds no allocator, TypeInfo, ModuleInfo, or D runtime
dependency.
Focused formatting passes; the repository-wide format check remains blocked
only by the existing mismatch in
`source/xtb/threading/internal/thread_linux.d`, which this feature does not
modify.
