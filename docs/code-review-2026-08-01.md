# Code review and remediation — 2026-08-01

## Current status

This file preserves the original adversarial review below so the reasons for
the changes remain inspectable. Every accepted finding that can be exercised
on the local x86-64 Linux host has now been remediated. The implementation was
not made compatible merely for compatibility's sake: the rejected C++
behaviors remain listed in `core-gap-analysis.md`.

The remediation landed in review-sized commits:

- `69cfc64` fixes aliased mutation and scratch-output conflicts;
- `f2c56f5`, `4aad509`, and `ad8a053` fix process-wide panic observation,
  exact subprocess diagnostics, and the strict build/test matrix;
- `4144b38` fixes the C allocator ABI and intrusive membership model;
- `3773fb2` separates optional diagnostics, removes internal demangler size
  ceilings, and makes crash installation transactional;
- `4d9cc46`, `26f1e20`, and `9867387` correct arena ownership, OS/resource
  semantics, and math contracts/numerics;
- `3d1f4b8` fixes one-pass formatting and logging semantics;
- `93bf354` centralizes the common BetterC attributes;
- `15d0d53` separates primitive aliases from numeric utilities and makes byte
  units ergonomic while keeping checked alternatives;
- `0732f5d` adds ASan/libFuzzer targets for demangling and mutable containers.

Two limitations are deliberate and documented rather than hidden. Module
qualifier omission uses D naming convention because linkage names do not encode
the module/aggregate boundary; exact output remains selectable. Linux's
attempted signal-context unwind remains explicitly best-effort, while the
fault-address-only mode is the deterministic restricted path.

Runtime execution has been completed on x86-64 Linux. AArch64 Darwin is locally
cross-compiled, not executed; native builders are still required before making
execution claims for Darwin or AArch64 Linux. Long-running fuzz campaigns are
also continuous verification work rather than a finite completion claim.

Final verification passed with LDC 1.41.0:

- `nix develop --command just check`;
- `nix build --print-build-logs`;
- `nix flake check --print-build-logs` on the locally compatible system;
- every Dub library and example configuration.

The gate includes strict warnings/deprecations, debug, optimized, and release
tests, exact panic/signal subprocess assertions, C ABI linkage, ASan, both fuzz
smoke targets, the AArch64 Darwin cross-build, and runnable examples. UBSan is
probed but explicitly skipped because this pinned LDC rejects
`-fsanitize=undefined`.

## Original verdict at review time

The project had a coherent BetterC direction, a useful explicit allocator
model, and substantially better tests than a typical early port. It was not yet
safe to treat as a production core library. The then-current test suite passed,
but targeted adversarial programs found memory-safety defects, a logger
corruption bug, and process/thread lifetime mistakes that the suite did not
exercise.

The ordering below is prescriptive. Fix the blockers before adding more library
surface. Do not preserve an API merely because it has already been written.

## Correctness blockers

### 1. Mutating string operations are unsafe with aliased input

`StringBuf.prepend` resizes before copying from `value`
(`source/xtb/core/string.d:720`). When `value` points into the buffer and the
resize reallocates, the final `memmove` reads freed storage. `tryEscape` has the
same defect: it reserves before iterating its borrowed input
(`source/xtb/core/string.d:747`). AddressSanitizer reproduced both as heap
use-after-free errors.

Make aliasing semantics uniform across every mutating `Array` and `StringBuf`
operation. The preferred rule is to support self-borrows: detect whether input
points into the allocation, retain offsets across growth, and copy in an order
that is correct for overlap. If a particular operation cannot support this,
reject it before changing the buffer and report an invalid argument rather than
misreporting an allocation failure. Add reallocating and non-reallocating alias
tests for append, prepend, insert, replace, and escape.

### 2. Path component append inherits the same use-after-free class

`tryAppendComponent` borrows `component`, then may grow `output` while adding a
separator before it appends the component (`source/xtb/os/path.d:67`). A
component borrowed from the output becomes dangling if that growth reallocates.
AddressSanitizer reproduced this defect.

Implement this only after the underlying `StringBuf` alias contract is fixed,
then add a path-specific self-borrow test.

### 3. OS output functions can return memory already rewound by scratch RAII

`executablePath` and `canonicalPath` acquire scratch with no allocator conflict
(`source/xtb/os/directory.d:227` and `:295`) while appending to a caller-owned
`StringBuf`. If that output uses the selected scratch arena and has to grow, the
inner `ScratchScope` rewinds the new output allocation on return. With rewind
poisoning enabled, a reproducer observed `0xDD` in the returned output.

Every function that holds an output or input alive across scratch work must
pass all relevant allocator handles to `ScratchScope.acquire`. These two
functions must at least use `ScratchScope.acquire(output.allocator)`. Audit all
other scratch acquisitions using this rule and add poison-enabled conflict
tests. Keep the API infallible when no arena is available; the required result
is a panic, as architecture.md specifies.

### 4. Recursive logging corrupts the outer record

`log` and `logf` format into the shared message buffer before `deliver` checks
the recursion flag (`source/xtb/core/logger.d:143-193`). A sink that logs again
overwrites the outer record while it is borrowed. The existing test verifies
the nested status but not the outer bytes; a reproducer changed `outer` to
`neste`.

Check `delivering_` before formatting. Strengthen the test to retain and compare
the outer record. Then document that `LogRecord.message` is borrowed only for
the duration of the sink call. If one `Logger` may be shared between threads,
provide synchronization or a serialized sink; otherwise explicitly make
single-thread ownership part of its contract.

### 5. Panic installation is thread-local while crash handling is process-wide

Unmarked module variables in D are TLS. Consequently `panicHook` and
`panicInFlight` (`source/xtb/core/panic.d:16`) are per-thread, but
`CrashHandlerScope` installs one process-wide crash configuration. A pthread
panic did not invoke the handler installed by the main thread, so it omitted
the rich panic stack trace.

Make the installed panic observer process-wide and define synchronization and
recursion behavior deliberately. A thread-local recursion guard may still be
useful, but it is a separate concern from the process-wide observer. Installation
and teardown must occur before worker creation/after worker joining, and tests
must panic on a worker thread.

`mallocAllocatorSlot` (`source/xtb/core/memory.d:20`) is accidentally TLS for
the same reason. Allocator-owning values can retain a pointer into a creator
thread's TLS after that thread exits. Make the immutable/stable malloc allocator
slot `__gshared`; it is process infrastructure, not thread state.

## High-priority redesigns

### Allocator ABI and lifetime

The allocator callback alias has D linkage, while the ABI test supplies a C
function pointer (`tests/abi_allocator.d`). That happens to work on the current
platform; it is not a sound ABI declaration. Declare the callback and all
foreign implementations `extern(C)` if C interoperability remains a goal.
Otherwise delete the C ABI claim and test. Validate both an allocator slot and
the function pointer stored in it at object construction boundaries.

The POD restriction added during this review is correct: typed bytewise
reallocation and `allocateZeroed!T` now reject elaborate types. Raw typed
allocation remains available so callers can explicitly construct elaborate
objects in returned storage.

### Intrusive collections cannot enforce their claimed membership invariant

A singleton node has null links even while linked, so it can be inserted into a
second list. Queue and stack have the analogous tail/singleton problem.
`containsNode` (`source/xtb/core/list.d:19`) searches only the destination and
cannot prove that a node is unlinked elsewhere. The searches also turn normal
pushes into O(n) operations and can loop forever after corruption.

Use a dedicated intrusive hook with owner/debug membership state, or make
unlinked membership a strict caller invariant and remove the misleading runtime
guarantee. Prefer the hook design for this safety-oriented library. Validate
link field types and mutability at compile time, not merely member names.

### Runtime contracts disappear in release builds

Public preconditions in math and some core helpers use `assert`, for example
`Random.below`, `perspective`, and `screenProjection`
(`source/xtb/math/random.d:32`, `source/xtb/math/matrix.d:321-334`). D release
builds remove these checks. Programmer errors must use the library's always-on
contract/panic facility. Reserve `assert` for internal facts whose removal
cannot make invalid public input unsafe. Add a real `-release` test target.

### Reading an entire file is not implemented for general files

`readEntireFile` sizes the output once from `fstat` and demands exactly that
many bytes (`source/xtb/os/file.d:301`). It returns empty for size-zero procfs
files, truncates files that grow, and turns shrink/short-read races into a
synthetic system error. Replace it with a chunked read-to-EOF loop with overflow
checks. A size hint may reserve capacity but must not define content length.

Also represent pre-epoch modification times without casting negative seconds
to `u64` (`source/xtb/os/file.d:296`).

### Diagnostics should not be mandatory core infrastructure

The `xtb.core` package publicly imports demangling, stack traces, and crash
handling (`source/xtb/core/package.d`), making every build compile diagnostics
and making Linux consumers link libbacktrace. This contradicts the intended
foundational dependency direction and contributes to cycles such as
`panic -> print -> memory -> panic` and `string -> array -> memory -> panic ->
print -> string`.

Move demangling, styling, stack traces, and crash installation under a separate
`xtb.diagnostics` package. Reduce the lowest panic/contract layer to libc writes
and core types; formatting belongs above it. Keep diagnostics opt-in and expose
its native link dependency through the package metadata.

### Demangling still has hidden length ceilings

The demangler uses fixed 1024-byte internal buffers
(`source/xtb/core/demangle.d:184`, `:456`, `:664`) and stack-trace rendering uses
a fixed 2048-byte demangle buffer (`source/xtb/core/stacktrace.d:346`). Valid long
symbols can therefore fall back to mangled names despite a caller providing
adequate storage. Eliminate internal fixed buffers. Parse into caller-provided
workspace or make a measurement pass followed by exact scratch allocation.

Module omission is also a casing heuristic (`source/xtb/core/stacktrace_style.d:438`):
it drops lowercase aggregate qualifiers and retains uppercase module names.
Carry structured module/aggregate roles out of the demangler instead.
`SignatureFormat.initialColumn` is currently dead; either make it affect the
line-width decision or remove it and correct the documentation.

### Crash installation needs transactional and concurrency semantics

If one `sigaction` call fails, earlier handlers remain installed
(`source/xtb/core/crash.d:138`). Roll back already-installed handlers before
panicking. Make global installation state changes race-free and document the
required lifecycle. `attemptStackUnwind` is appropriately named as a best-effort
mode because platform unwinding is not guaranteed signal-safe; keep the
fault-address-only path minimal.

## API and behavior corrections

- `tryFormatString` formats custom values twice—once to measure and once to
  render (`source/xtb/core/print.d:284`). A stateful formatter can produce side
  effects twice or a different size. Prefer a one-pass `StringBuf` writer, or
  explicitly require measurement-stable formatting and test it.
- Allocator-backed functions that return a plain `String` make ownership and
  deallocation size easy to lose, especially after slicing. Prefer `StringBuf`
  for malloc-owned results and plain `String` for borrowed or arena-lifetime
  values. Keep `String`, `StringBuf`, and `Array` as requested.
- Specify the zero state honestly: a zero `StringBuf` can be queried or cleaned
  up, but cannot grow until an allocator is installed. Document that `cString`
  returns a terminator valid only until mutation.
- `stripExtension(".bashrc")` currently treats the leading dot as an extension.
  Adopt the common rule that a leading dot alone does not start an extension.
- Add explicit error-returning `close`/`unmap` operations for resources whose
  destructor cannot report cleanup failure. Keep destructors as best-effort
  fallback.
- Replace boolean policy arguments such as `followLinks` and `exclusive` with
  enums. Normalize output state on every failure and make `fromErrno(0)` mean no
  error.
- `panicf` silently truncates at 1024 bytes (`source/xtb/core/panic.d:54`). At
  minimum append a visible truncation marker; preferably keep the primitive
  panic path allocation-free while allowing the rich diagnostics layer a
  larger caller-provided buffer.
- File logging emits one record through several `fwrite` calls, permitting
  interleaving. Emit a prepared record atomically where the platform permits or
  serialize the sink. Rename `fatal` to `critical` unless logging at that level
  terminates.

## Math corrections

- The `rotation(yaw, pitch, roll)` implementation applies Z/Y/X
  (`source/xtb/math/matrix.d:282`), which conflicts with the library's
  direction convention. Delete the ambiguous overload or explicitly define and
  implement yaw-Y, pitch-X, roll-Z with a named composition order.
- `translated`, `scaled`, and `rotated` pre-multiply without making world/local
  semantics visible. Use explicit `preTranslated`/`postTranslated` names (and
  equivalents) or expose only matrix multiplication.
- Norm calculation overflows for large finite vectors. Use scale-stable norms;
  otherwise normalization can yield zero and angles can be wrong.
- `lookAt` silently creates a degenerate matrix when eye equals target or up is
  parallel to the view. Provide `tryLookAt` plus a panicking wrapper.
- Validate finite values and `0 < verticalFov < PI` for perspective projection.
  Define a singularity tolerance policy for inverses.
- `Random.between` can overflow `upper - lower` for valid finite endpoints. Use
  a numerically safer interpolation and define endpoint/NaN behavior.
- Matrix inverse tests currently inspect mostly diagonal entries. Compare the
  complete product to identity and add randomized/property tests.

## Build, testing, and code quality

The canonical `just` and Nix builds omit `-preview=dip1000`, while Dub enables
it. They use `-wi` rather than warnings-as-errors. `just check` omits the ASan
target and has no `-release` run. Nix checks omit sanitizer, lint, examples, and
the Darwin cross-build. Align every build entry point around one flag set and
make the strict release, ASan, lint, ABI, and supported cross-build matrix part
of `flake check`.

`just format` covers only math, OS, and selected runners. The default `dfmt`
configuration also reformats core signatures poorly; pin a repository
configuration before expanding coverage, then format all D source, tests, and
examples. Do not keep the current source-order workarounds that compile every
module into every runner; give packages explicit source lists or generate them
from a single manifest.

The death-test helpers need repair:

- `expectDeath` accepts any nonzero status, including `execl` failure and an
  unknown case (`tests/core_tests.d:148`). Require the expected signal/status.
- `captureDeath` stops reading once its 32 KiB storage is full, closes the pipe,
  and then waits (`tests/core_tests.d:183`). A verbose child can block on the
  full pipe. Continue draining while discarding bytes beyond captured capacity,
  and record truncation.
- Expected panic text should be captured, not spam the normal test log.

Add adversarial tests for every reproduced defect, compiler `-release` tests,
long-symbol tests, property tests for math, allocator-failure tests at each
allocation point, and fuzz targets for the demangler and mutating containers.
Avoid relying on explicit runner imports without a check that every module with
unittests is actually included.

Attribute style is too noisy and safety boundaries are too implicit. Use
module/section attribute blocks for the common `nothrow @nogc` policy, as the
user requested. Do not blanket-mark unsafe modules: isolate pointer/libc code in
small explicit `@system` blocks and expose audited `@trusted` wrappers where
appropriate. The project compiles with DIP1000 today, but `-preview=safer`
reveals extensive dependence on implicit `@system`; treat that as boundary
inventory, not as a flag to enable blindly.

## Validation performed

The following passed on x86_64 Linux with LDC 1.41.0:

- `nix develop --command just check`;
- `nix develop --command just test-sanitize`;
- `nix flake check --print-build-logs` for the locally buildable system;
- Dub debug library build;
- strict `-preview=dip1000 -w -de` compilation;
- an explicit `-release` compilation.

Passing those commands does not invalidate the blockers above; the alias,
recursive logging, scratch-conflict, cross-thread panic, and elaborate zeroing
failures required targeted reproducers absent from the checked-in suite.

## Recommended implementation order

1. Fix the three alias/scratch memory-safety groups and add ASan regressions.
2. Correct process-wide panic/allocator state and recursive logging, with
   pthread tests.
3. Repair death tests and make strict release plus ASan mandatory checks.
4. Split diagnostics from core and break the panic/print/memory dependency
   cycle.
5. Correct allocator ABI and intrusive membership semantics.
6. Replace `readEntireFile`, normalize OS ownership/error contracts, and add
   explicit cleanup APIs.
7. Remove demangler length ceilings and the module-name heuristic.
8. Make math conventions explicit and add full-matrix/property coverage.
9. Pin formatting/lint policy, consolidate build manifests, and finish public
   Ddoc for ownership and lifetime rules.
