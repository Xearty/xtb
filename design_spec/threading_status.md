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
| 2 | **next** | Raw thread layer and Linux backend | — | `Thread.startRaw`/`startRawWith`, lifecycle, join/detach, `ThreadId`, start options/errors, `currentThreadId`, `yieldThread`, `hardwareConcurrency`, and naming. |
| 3 | pending | Processor relaxation | — | `cpuRelax`; kept separate from scheduler yielding. |
| 4 | pending | Internal parking | 1 | Linux process-private futex compare-and-sleep plus wake-one/wake-all. |
| 5 | pending | Atomic wait/notify and startup latch | 1, 4 | Public `Atomic.wait`/notify plus the allocation-free internal one-shot start latch. |
| 6 | pending | `SpinWait` | 2, 3 | Bounded exponential processor relaxation followed by scheduler yield. |
| 7 | pending | Typed zero-allocation `Thread.start` | 2, 5 | Typed by-value capture, stack-packet handoff, callable/parameter constraints, and `startWith`. |
| 8 | pending | `Mutex` | 1, 2, 3, 4 | Fast acquire, bounded relax-then-park slow path, checked owner diagnostics. |
| 9 | pending | `ConditionVariable` | 4, 8 | Atomic unlock/wait/relock protocol, notify-one/all, checked mutex association. |
| 10 | pending | `Semaphore` | 1, 4, 5 | Counting permits, overflow protection, efficient blocking wakeups. |
| 11 | pending | `Once` | 1, 4, 5 | Exactly-once execution with publication and recursive-use diagnostics. |
| 12 | pending | `OnceCell!T` | 11 | Allocation-free typed one-time initialization and exact manual lifetime handling. |
| 13 | pending | `Latch` | 1, 4, 5 | First public countdown primitive; one-shot countdown/wait semantics. |
| 14 | pending | Internal countdown/generation machinery | 13 | Refactor proven countdown path and add reusable generation state. |
| 15 | pending | `WaitGroup` | 14 | Dynamic registration, reuse across generations, underflow/reuse misuse checks. |
| 16 | pending | `Barrier` | 14 | Reusable generations, arrival/drop semantics, permanent completion. |
| 17 | pending | `RwLock` | 1, 4 | Writer-preference reader/writer lock and checked writer-owner diagnostics. |
| 18 | pending | `spawn` and `JoinHandle!T` | 2 | Explicit allocator-backed typed result transport and move-only join ownership. |
| 19 | pending | `threadScope` | 2, 18 | Allocator-backed heterogeneous child tracking, scoped borrowing, guaranteed join-all. |
| 20 | pending | Lock guards | 8, 17 | `LockGuard`, `ReadLockGuard`, and `WriteLockGuard` with move-only lexical ownership. |
| 21 | blocked | Monotonic time, sleeping, and timed waits | time foundation | Requires a stable monotonic-time abstraction that preserves the threading package dependency direction. |
| 22 | pending | Windows backend coverage | public contracts above | Implement every completed OS-dependent primitive/utility with the same public semantics. |

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

## Prototype gates

| Gate | Status | Required before | Result / notes |
|---|---|---|---|
| Atomic backend widths / direct operations | **complete for LDC 1.42.0 x86_64 Linux** | Feature 1 | Probed 1/2/4/8-byte integral and enum values plus native pointers; LDC emitted native atomic instructions with no unresolved `__atomic*` runtime calls in the probe. |
| Atomic/shared receiver behavior | **complete for Feature 1** | Feature 1 | D requires distinct shared and unshared receiver overloads. `Atomic!T`/`AtomicFlag` expose both, with qualifier casts contained inside trusted atomic boundaries. |
| Static memory-order diagnostics | **documented language/API limitation** | Feature 1 | The specified public syntax passes `MemoryOrder` as a runtime value. D semantic analysis does not preserve whether that argument originated from an enum literal, so the implementation cannot reject a literal invalid order at compile time without changing the call syntax to template value parameters. All invalid orders/combinations are still unconditional programming-error panics. |
| Parameter storage-class introspection | pending | Feature 7 | Probe `ref`, `out`, `lazy`, `scope`, `return`, and current `in` behavior under the supported frontend. |
| LDC-created-thread TLS | pending | Raw/typed thread TLS guarantees | Must be tested with a thread created without druntime thread startup. |
| Native thread naming limits/error mapping | pending | Feature 2 naming freeze | Verify Linux behavior and portable error mapping; do not expose Linux limits as portable constants. |
| Scoped structured-borrow syntax | pending | Feature 19 | Prove BetterC/no-GC closure behavior and non-escape properties or use the explicit context fallback. |
| Broader `shared`/`inout` policy | pending | Cross-primitive API freeze | Feature 1 records only the atomic-specific result; mutex-protected object graphs and typed worker arguments still need focused experiments. |

## Repository cleanup status

The stale `Option.set` call sites that were present in the supplied snapshot have
been migrated to the current explicit `some(...)` assignment API in `xtb.os`,
serde tests, and the serde example. The OS and serde debug runners now compile
and pass alongside the other test targets.

The repository-wide D-Scanner 0.15.2 policy pass is clean for every file that
version can parse. `source/xtb/core/pretty_print.d` and
`examples/pretty_print_demo.d` are excluded through the existing `dscanner.ini`
compatibility mechanism because D-Scanner 0.15.2 cannot parse the interpolation
sequence syntax they use; LDC continues to compile-check both files. The real
style/static-analysis findings previously reported in core `result.d`, the
intrusive-list layout assertions, parser, and TOML have been fixed.

The repository still has pre-existing dfmt drift in files unrelated to threading;
that formatting-only cleanup is intentionally not folded into feature work.
