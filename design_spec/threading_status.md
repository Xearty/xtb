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
| 5 | **next** | Typed zero-allocation `Thread.start` | 2, 4 | Stack-packet/latch handoff for `start`/`startWith`. Typed callable/parameter/capture rules are already exercised by the allocator-backed `startAlloc` path from Feature 2. |
| 6 | pending | `SpinWait` | 2 | Bounded exponential processor relaxation followed by scheduler yield. |
| 7 | pending | `Mutex` | 1, 2, 3, 6 | Fast acquire, bounded relax-then-park slow path, checked owner diagnostics. |
| 8 | pending | `ConditionVariable` | 3, 7 | Atomic unlock/wait/relock protocol, notify-one/all, checked mutex association. |
| 9 | pending | `Semaphore` | 1, 3, 4 | Counting permits, overflow protection, efficient blocking wakeups. |
| 10 | pending | `Once` | 1, 3, 4 | Exactly-once execution with publication and recursive-use diagnostics. |
| 11 | pending | `OnceCell!T` | 10 | Allocation-free typed one-time initialization and exact manual lifetime handling. |
| 12 | pending | `Latch` | 1, 3, 4 | First public countdown primitive; one-shot countdown/wait semantics. |
| 13 | pending | Internal countdown/generation machinery | 12 | Refactor proven countdown path and add reusable generation state. |
| 14 | pending | `WaitGroup` | 13 | Dynamic registration, reuse across generations, underflow/reuse misuse checks. |
| 15 | pending | `Barrier` | 13 | Reusable generations, arrival/drop semantics, permanent completion. |
| 16 | pending | `RwLock` | 1, 3 | Writer-preference reader/writer lock and checked writer-owner diagnostics. |
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
pointer and user context, publishes completion with release ordering, and only
then calls user code; the parent observes that publication with acquire ordering
before returning. It waits only for ABI packet capture, never for worker
execution.

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

The supplied LDC 1.42.0 druntime headers expose `syscall` but not `SYS_futex`, so
the Linux parking module contains the stable Linux syscall-number mapping for
target architectures it recognizes and otherwise compiles with an explicit
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
existing raw-thread bootstrap handoff to `StartLatch` remains a separate
refactoring commit so this commit contains only the primitive and its tests.

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
