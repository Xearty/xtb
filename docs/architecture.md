# Architecture

## Runtime-check policy

Programmer contracts use `require`, with both the import and call guarded by
`version (XTB_Checked)`. Debug and release-safe builds define that identifier;
release-fast omits it and also disables native assertions, contracts, and array
bounds checks. The guard must remain at the call site so contract arguments are
not evaluated in release-fast. Recoverable validation and explicit panic paths
are independent of this policy. See `docs/build-modes.md`.


## Purpose

`xtb` is an independent D library collection inspired by the capabilities of
the archived C++ project under `archive/cpp`. It is not a line-for-line port
and must never import, generate from, or build files in that project. Design
new APIs around D's strengths while keeping every production target compatible
with `-betterC`.

BetterC removes the garbage collector, exceptions, classes, `TypeInfo`,
`ModuleInfo`, associative arrays, built-in threading, and module constructors.
These are architectural constraints, not merely compiler settings. The build
and test paths both compile with `-betterC` so violations are caught early.

## Repository shape

Use conventional D package layout:

```text
xtb/
├── source/xtb/             # production modules
│   ├── core/               # memory, containers, text, printing, logging
│   ├── diagnostics/        # demangling, styled traces, crash observation
│   ├── math/               # vectors, matrices, scalar algorithms, noise
│   ├── os/                 # general libc and platform adapters
│   ├── threading/          # threads, atomics, and synchronization backends
│   ├── serde/              # attribute-driven structured data mapping
│   ├── codec/              # image, audio, compression, and byte formats
│   ├── window/             # window/input abstraction
│   ├── graphics/           # graphics API adapter and resources
│   └── renderer/           # backend-independent rendering policy
├── tests/                  # runners, fixtures, integration/regression tests
├── examples/               # small programs using only public APIs
├── docs/
├── archive/cpp/            # read-only historical C++ implementation
├── dub.sdl
├── flake.nix
└── justfile
```

The initial migration may create only the directories it needs. Do not add
empty placeholder modules. A source path maps directly to its module name; for
example, `source/xtb/core/memory.d` declares `module xtb.core.memory;`.
Use narrowly focused modules rather than umbrella modules with implementation.
An optional `xtb.core` module may publicly import a deliberately small stable
surface, but internal modules must import their precise dependencies.

Each component directory under `source/xtb` owns a colocated DUB recipe that
positively lists only its sibling production modules. Non-core components
declare `xtb:core` as a package dependency when needed. Do not partition the
tree by starting with every source and subtracting unrelated directories with
`excludedSourceFiles`; adding a new component must not change an existing
component's source set. The root recipe builds the aggregate `xtb` library.
`examples/dub.sdl` and `tests/dub.sdl` separately select the sources needed by
each runnable example and explicit BetterC runner.

## Dependency direction

Dependencies flow downward:

```text
examples / applications
      /              \
 renderer         diagnostics
 /      \              |
graphics window        |
 \      /               |
serde / codec / os / threading
      |          |        |
     math        |        |
       \        |       /
             core
              |
          C ABI / libc
```

- `core` depends only on language features and selected `core.stdc` bindings.
- `diagnostics` depends on `core` plus its explicitly selected platform
  unwinder. Core must never import diagnostics or require libbacktrace.
- `math` depends on `core` only when it needs shared primitive/result types.
- `threading` depends on `core` and owns the narrow native thread/parking
  boundary required to implement its public contracts. It must not depend on
  `os`; `os` may later depend on `threading`, so reversing that edge would risk
  a cycle.
- `os` owns general operating-system and libc facilities. Other components do
  not call libc directly unless they are themselves a deliberately isolated
  foreign/platform boundary, such as the native backend inside `threading`.
- `serde` maps user-defined values to structured key-value formats. Its schema
  and ownership rules are format-neutral; JSON, TOML, and future binary
  backends provide syntax and representation policy.
- `codec` transforms domain-specific byte formats such as images, audio, or
  compressed data. It does not contain reflection-driven object mapping.
- `window` wraps the chosen native window/input library and exposes opaque
  handles and value events.
- `graphics` owns the graphics backend, GPU handles, and backend-specific
  translation. OpenGL/Vulkan identifiers must not leak into `renderer` APIs.
- `renderer` coordinates resources and draw policy through `graphics`; it may
  depend on `codec`, `math`, and `core`, but lower layers never import it.

Cycles are forbidden. If two packages need the same type, move the smallest
neutral abstraction downward rather than adding mutual imports. Foreign
bindings live beside their adapter (for example `xtb.graphics.opengl.binding`)
and are not treated as general-purpose core modules.

Within core, `xtb.core.types` is a dependency-free leaf containing only the
primitive aliases, including `String`. `xtb.core.lifetime` owns the explicit
`deinit` protocol, `needsDeinit`, and XTB move/replacement primitives.
`xtb.core.memory` owns the type-erased `Allocator` callback contract and generic
allocation/reallocation/disposal helpers, delegating typed finalization to the
lifetime layer. Concrete allocator implementations are grouped under
`xtb.core.allocators.*`: `malloc` provides the libc-backed allocator, `arena`
provides arena allocation, and `instrumented` provides deterministic
allocation tracking/failure injection. This lets APIs depend on the allocator
contract without importing a concrete allocation policy. Generic scalar and
checked-arithmetic operations live in `xtb.core.numeric`; that module may use
the panic contract layer without forcing panic to depend on containers or
builders. `xtb.core` publicly imports the allocator aggregate for convenience,
while implementation modules import the narrow module that owns the declaration
they use.

The ordinary byte-unit helpers return their result directly and panic on
overflow:

```d
size_t bytes = mebibytes(4);
```

Code that genuinely recovers from an unrepresentable size uses the explicitly
fallible `tryKibibytes`, `tryMebibytes`, `tryGibibytes`, or `tryTebibytes`
variant with an output pointer. Their output is reset to zero on arithmetic
failure. The multiplication helper is private; callers should not manually
assemble a unit conversion protocol around a generic `scaleBytes` function.

`xtb.core.duration` owns the platform-neutral `Duration` value. A `Duration`
is a finite, nonnegative span stored as nanoseconds in one `u64`; it is not a
wall-clock timestamp, monotonic instant, deadline, or representation of
infinity. `Duration.init` is zero. Construct values with explicit unit helpers
such as `milliseconds(250)` and `seconds(2)`. Floating-point counts are rejected
at compile time so conversion never hides rounding policy.

Duration addition, subtraction, integral multiplication, and integral division
return values directly. Negative input, division by zero, underflow, and
overflow are contract violations and panic. Queries beginning with `whole`,
such as `wholeMilliseconds`, deliberately truncate the smaller remainder;
`totalNanoseconds` is exact. APIs that need an infinite or immediate wait use a
separate tagged policy value around `Duration` rather than assigning sentinel
meanings to `Duration.init` or `Duration.max`.

## Math and deterministic noise

`xtb.math` is a BetterC value layer. `Vector2`, `Vector3`, `Vector4`,
`Matrix2`, `Matrix3`, and `Matrix4` are tightly packed `float` values with no
allocator, destructor, runtime type information, or hidden initialization.
Use native construction and operators rather than dimension-suffixed helper
names. Algorithms are free functions designed for UFCS, such as
`direction.normalized`, `matrix.transposed`, and `value.projectedOnto(axis)`.

Matrices are column-major and multiply column vectors. `a * b * point` applies
`b` before `a`; transform-building code must preserve that order explicitly.
Projection functions use the OpenGL-style right-handed clip convention with
depth in `[-1, 1]`. Inversion is fallible and writes through an explicit
output pointer: singular matrices return `false` without fabricating a matrix.
The output remains untouched on failure. Inversion normalizes the input scale
and rejects pivots or normalized determinants at or below
`inverseRelativeTolerance`, currently eight float epsilons; callers needing
ill-conditioned matrices must use a wider representation or domain-specific
solver. The affine inverse additionally rejects non-affine inputs.

Vector lengths use scale-normalized norms so large or subnormal finite vectors
do not overflow or underflow merely while being normalized. `tryLookAt` rejects
non-finite inputs, coincident eye/target positions, zero up vectors, and up/view
directions parallel within the inverse tolerance. `lookAt` is the panicking
wrapper for call sites where such input is a programming error.

`rotationYawPitchRoll` uses radians and composes local roll about +Z, then pitch
about +X, then the library's clockwise-positive yaw about +Y; applying it to
the default forward vector agrees with `directionFromDegrees`. Transform UFCS
helpers state multiplication side explicitly: `preTranslated` means
`translation * base`, while `postTranslated` means `base * translation`, with
equivalent names for scale and rotation.

`Random` implements a stable PCG32 sequence. Callers always supply a seed and
may supply an independent stream; there is no process-global random state.
`unit()` returns values in `[0, 1)`, and `below(bound)` uses rejection sampling
instead of modulo-biased range reduction. `between` requires finite ordered
endpoints and uses sign-aware interpolation, so the full `[-float.max,
float.max]` range does not overflow while forming its span.

`ValueNoise1D` owns its periodic lattice through an explicit `Allocator*` and
is non-copyable. Its integer lattice values lie in `[-1, 1]`; `sample` uses a
smootherstep interpolation and accepts negative finite coordinates. A seed and
stream fully determine its values. The period is measured in lattice cells,
must be nonzero, and is capped at the largest integer exactly representable by
`float`, so `sample(x) == sample(x + period)` remains meaningful. Allocation
failure is exposed only by `tryCreate`; `create` panics consistently with other
owning containers.

## Operating-system boundary

`xtb.os` is the only general-purpose package that calls operating-system APIs.
Its public interface uses `Path`, a trivially copied borrowed view that rejects
embedded NUL bytes. A `Path` owns no storage; callers keep its source alive
exactly as they would for `String`. Joining does not normalize, resolve links,
or silently access the filesystem.

POSIX calls need temporary NUL-terminated text. The Linux backend obtains that
storage from the explicitly installed thread context through `ScratchScope`;
path-based OS operations therefore require `ThreadContextScope` on the calling
thread. Returned handles, mappings, metadata, and copied output never retain
scratch storage.

Expected failures return `OsError`, containing a portable category and native
code. A successful existence or permission query may write `false`; absence
and denied access are query results rather than failures. Unsupported backends
return `OsErrorKind.unsupported` while retaining the API and allowing the whole
library to compile.

`File`, `DirectoryIterator`, and `MappedFile` are non-copyable RAII owners with
valid empty states and idempotent `deinit`. Operations that mutate or advance
them take explicit pointers. `IoResult` distinguishes partial progress from
failure; complete I/O loops over short transfers and interruptions. Explicit
`close` and `unmap` operations report cleanup errors, while destructors are
best-effort fallbacks. Whole-file helpers use caller-owned `Array!ubyte`, read
until EOF, preserve embedded NUL bytes, and make allocation explicit. File
metadata is only a capacity hint and never defines how many bytes exist.

Policy choices use enums: `CreateMode` distinguishes opening, creating when
missing, and creating a new file exclusively; `SymlinkMode` states whether
metadata follows a symbolic link. Do not replace these with positional Boolean
arguments.

Directory enumeration is streaming. `DirectoryEntry.name` borrows libc's entry
buffer and expires when the iterator advances or closes. There is deliberately
no linked-list result. `walkDirectory` performs depth-first traversal through a
non-allocating callback receiving a temporary full `Path`; that path must not
escape the callback. Traversal receives an explicit temporary allocator so
arbitrary directory depth does not consume nested scratch arenas. It reuses one
path buffer per active depth, keeping monotonic-arena consumption proportional
to depth rather than entry count. Callers needing persistence copy entries into
their chosen container and allocator.

`environmentVariable` is the validated `String` wrapper around the platform
environment. It rejects empty names, `=`, and embedded NUL, reports absence as
`OsErrorKind.notFound`, and returns a process-owned borrowed view that later
environment mutation can invalidate. Converting its `String` name to a C
string uses scratch space, so the public operation requires an installed
thread context. Raw `getenv` pointers remain package-private OS boundaries.
`currentDirectory`, `executablePath`, and
`canonicalPath` write owned bytes into a supplied `StringBuf`. Read-only maps
remain valid until their `MappedFile` is destroyed. Monotonic timestamps serve
elapsed-time measurement; wall-clock and file-modification timestamps are
signed Unix-epoch nanoseconds, represent pre-epoch values, and may jump when
the system clock changes.

`shouldUseAnsi(FILE*, AnsiMode)` owns terminal-color policy; the core logger
does not inspect file descriptors or environment variables. `automatic`
requires a POSIX terminal according to `isatty`, rejects `TERM=dumb`, and
honors a non-empty [`NO_COLOR`](https://no-color.org/) value. It conservatively
returns `false` on platforms without a locally implemented detector. `always`
and `never` are explicit overrides. The result is composed with the normal
core logger factory rather than hidden behind a second logger abstraction:

```d
const logStyle = shouldUseAnsi(stderr)
    ? LogStyle.ansi : LogStyle.plain;
Logger logger = stderrLogger(storage[], LogLevel.info, logStyle);
```

`Command`, `Environment`, and the standard-stream route types are borrowed
process descriptions. Spawn validates them, builds native argv/environment
storage in an internal `ScratchScope`, and returns a non-copyable
`ChildProcess`. A child owns both its direct-child reap obligation and any
parent pipe endpoints created by `piped` routes. Successful waits consume only
the reap obligation so remaining output can still be drained. Dropping a live
child is a last-resort force-kill-and-reap operation; ordinary code explicitly
waits or terminates so errors and exit status remain observable. Process output
is bytes, never implicitly a `String`, because arbitrary programs may emit NUL
or invalid UTF-8.

`communicate` drives nonblocking child stdin, stdout, stderr, and process
readiness together. Its `CaptureBuffer` values borrow fixed caller storage;
when storage fills, communication records truncation and continues draining so
the child cannot deadlock. Input and capture storage must not overlap. Timeout
states distinguish resumable ownership from policies that terminate and reap.

`Pipeline` owns allocator-backed child and status slots while borrowing its
`Command[]` or `PipelineStage[]` only during `spawnPipeline`. Intermediate
parent pipe ends close as soon as the adjacent child has inherited its mapping.
The owner records statuses in stage order and applies either last-stage or
every-stage success policy. Its blocking wait has the same output-drain warning
as `ChildProcess.wait`; managed multi-stream pipeline communication remains a
separate later layer.

## BetterC design rules

### ABI and entry points

Library APIs use the D ABI by default. Apply `extern(C)` only to exported C
entry points, callbacks, and declarations that cross a C ABI. Keep ABI structs
plain, fixed-layout values and use fixed-width integer types. Do not expose a D
delegate, dynamic array, or compiler-specific enum representation through a C
boundary; use pointer-plus-length and explicit function-pointer/context pairs.

Executable entry points are `extern(C) int main(int argc, char** argv)` (or the
platform equivalent). Startup is explicit: no module constructors or implicit
registration.

### ANSI terminal styling

`xtb.core.ansi` only encodes Select Graphic Rendition control sequences; it
does not assume that a destination is a terminal. `AnsiColor` supports the
terminal's named 16-color palette, indexed 256-color values, RGB values, and
the terminal's default color. `AnsiColor.init` emits nothing, which makes the
zero state useful. `AnsiStyle` combines foreground and background colors with
bold, dim, italic, underline, blink, reverse, hidden, and strikethrough
attributes. Its attribute storage is `FlagSet!AnsiAttribute`, not an unrelated
second bit-mask implementation.

Styles are allocation-free values. Builder operations return a changed copy:

```d
const heading = AnsiStyle.foreground(AnsiColor.brightCyan).bold;
const diagnostic = AnsiStyle.foreground(AnsiColor.rgb(255, 95, 95))
    .withBackground(AnsiColor.indexed(234))
    .underline;

write(heading, "heading", ansiReset, "\n");
write(diagnostic, "diagnostic", ansiReset, "\n");
```

`beginAnsi`/`endAnsi` serve `Writer`-based renderers. `ansiSequence` and
`ansiResetSequence` return fixed-capacity stack values for lower-level sinks,
including the fatal-signal renderer; they do not allocate or call stdio.
Ending a style emits a full SGR reset rather than restoring an enclosing style,
so callers that nest styles must explicitly reapply the outer style.

### Diagnostics and fatal crashes

Logging has an explicit foundation and an optional per-thread convenience
layer. `Logger` owns no sink or message storage: it borrows a callback/context
pair and a caller-provided formatting buffer. Library code that accepts more
than one independent log destination, exposes logging as a dependency, or may
run without a `ThreadContext` should accept and call an explicit `Logger`.

Applications may install one as the current logger in an existing thread
context:

```d
ThreadContextScope context = ThreadContextScope.acquire();
char[1024] logStorage;
Logger applicationLogger = stderrLogger(
    logStorage[],
    LogLevel.info,
    shouldUseAnsi(stderr) ? LogStyle.ansi : LogStyle.plain,
);
ThreadLoggerScope logging = ThreadLoggerScope.install(&applicationLogger);

log(LogLevel.info, "application started");
logf!"loaded {} records"(LogLevel.debug_, recordCount);
```

`ThreadLoggerScope` borrows the `Logger`; the logger and its formatting buffer
must outlive the scope. Its destructor restores the previously installed
logger, so a nested scope can temporarily redirect a thread's output. Scopes
must unwind before `ThreadContextScope` and in reverse installation order.
Installing a null or invalid logger, installing without a thread context, or
violating destruction order is a programming error and panics in checked build
modes. Release-fast assumes correct scope ordering.

The overloads without a `Logger` receiver—`enabled(level)`, `log(level, ...)`,
`logf!pattern(level, ...)`, and `flushLogger()`—consult only the calling
thread's context. With no installed logger, `enabled` and `flushLogger` return
`false`, while logging returns `LogStatus.invalidLogger`; it does not silently
write to stderr or manufacture persistent storage. Filtering happens before
formatting. The original `logger.log(...)`, `logger.logf!pattern(...)`, and
`logger.flush()` APIs remain available and do not consult TLS.

File logger coloring is explicit. `LogStyle.plain`, the core default, never
emits control sequences. `LogStyle.ansi` applies one `AnsiStyle` to the entire
`[level] message`, followed by a reset before the newline. `LogPalette`
contains independently configurable styles for all six levels;
`LogPalette.defaults()` supplies a readable named-color palette and makes
critical messages bold. All logger creation functions use that palette when
the argument is omitted. Passing a modified value configures a logger without
global state:

```d
LogPalette palette = LogPalette.defaults();
palette.warning = AnsiStyle.foreground(AnsiColor.rgb(255, 175, 0)).bold;
Logger logger = stderrLogger(
    storage[],
    LogLevel.trace,
    LogStyle.ansi,
    palette,
);
```

Formatting buffers and `LogRecord.message` never contain ANSI bytes. Styling
is presentation metadata applied by the ANSI file sink, so plain file sinks
and application-defined capture sinks retain clean messages. `LogResult`
counts formatted message bytes, not prefix, newline, or presentation escapes.

Normal call sites should use the level-specific convenience functions instead
of spelling `LogLevel` repeatedly. The plain family forwards to `log`, and the
`f` family forwards to the compile-time `{}` form of `logf`:

| Level | Plain arguments or interpolation | Compile-time `{}` pattern |
| --- | --- | --- |
| trace | `trace(...)` | `tracef!pattern(...)` |
| debug | `debug_(...)` | `debugf!pattern(...)` |
| info | `info(...)` | `infof!pattern(...)` |
| warning | `warning(...)` | `warningf!pattern(...)` |
| error | `error(...)` | `errorf!pattern(...)` |
| critical | `critical(...)` | `criticalf!pattern(...)` |

Every function has both an explicit UFCS form and a current-thread form:

```d
logger.info(i"opened $(path)");
logger.errorf!"operation failed with code {}"(code);

info(i"opened $(path)");
errorf!"operation failed with code {}"(code);
```

`debug_` has a trailing underscore because `debug` is a D keyword; the
formatted name `debugf` needs no escape. These wrappers add no filtering,
formatting, storage, or failure semantics of their own. Keep `log` and `logf`
for code where the level is selected dynamically.

An installed logger is not owned and does not become thread-safe. Each thread
normally owns a distinct `Logger` and message buffer. File sinks serialize the
final file write, but sharing one `Logger` between threads would still race on
its formatting buffer, filter state, and recursion guard. Cross-thread logging
uses distinct logger values whose sinks perform whatever synchronization the
destination requires.

Stack traces use caller-provided frame and text storage. Symbol capture,
demangling, signature tokenization, styling, and rendering must not allocate.
`writeStackTrace` additionally receives a caller-owned signature workspace,
which it reuses for every frame. A workspace too small for one complete name
causes that frame to retain its mangled linkage name; it never inserts `...`.
The D demangler implements relative identifier/type back-references, template
types and values, qualifiers, arrays, pointers, functions, delegates, tuples,
calling conventions, parameter storage classes, and function attributes. It
writes into caller storage and returns the untouched linkage name only when the
symbol is malformed, is not D-mangled, or exhausts the destination. It must
never shorten a valid signature with a placeholder. A diagnostic never trusts
an encoded length, count, or relative offset without checking it against the
remaining input and a fixed recursion limit.

`SignatureDetail.overloadIdentity` is the default for stack traces and direct
demangling. It discards the outer function's return type and function
attributes because they do not distinguish overloads. It retains parameter
storage classes and the member-function `const`, `immutable`, `shared`, or
`inout` qualifier. Function and delegate types nested inside parameters remain
complete—including their return type, calling convention, and attributes—
because those properties participate in parameter-type matching. Alias
template arguments naming functions use the same overload-oriented form.
Select `SignatureDetail.full` through `StackTraceStyle.signatureDetail`,
`CrashHandlerOptions.signatureDetail`, or the final `tryDemangleD` argument
when diagnostic output should include every encoded return type and attribute.
`SignatureDetail.overloadIdentityAndReturn` is the middle ground for readable
diagnostics: it adds the outer return type to the overload identity but still
omits outer function attributes.

`StackTraceStyle.signatureLayout` defaults to `SignatureLayout.multiline`, with
`signatureColumns = 100`. If the outer signature exceeds that width, it is
formatted like a D declaration: the opening parenthesis ends the first line,
every outer parameter occupies a separate line indented four spaces, and the
closing parenthesis begins the final line. The return type and outer function
attributes, when enabled by `SignatureDetail`, remain after that closing
parenthesis. Nested function, delegate, qualifier, and template argument lists
remain intact within their containing parameter. Width checks count visible
signature bytes rather than ANSI escape-sequence bytes; the frame index and
its indentation do not count toward the limit. A signature whose visible width
is exactly the configured limit remains on one line. Select
`SignatureLayout.singleLine` for machine-oriented output or terminals that
handle horizontal scrolling. Direct `writeSignature` callers configure the
same behavior with `SignatureFormat.maxColumns` and `continuationIndent`. A
zero column limit is treated as unbounded.

```text
Renderer.submit(
    ref Context,
    scope const(Command)[],
    CompletionHook
) -> RenderResult nothrow @nogc
```

`StackTraceStyle` owns no text or allocation. Its `StackTraceColors` use the
shared core `AnsiColor`; presets contain indexed colors from `fromAnsi8`, while
custom styles may also use named or RGB colors. Both rich rendering and the
low-level fatal-signal path encode them through `xtb.core.ansi`. Rendering uses
a plain theme when ANSI control sequences are inappropriate. Signature
coloring is lexical presentation only; failure to classify a token never
changes or discards the token's source bytes.

The preset catalog is `solar`, `warmAsh`, `zenburn`, `gruvbox`, `tokyoNight`,
`nord`, `dracula`, `oneDark`, `monokai`, `catppuccinMocha`, `everforest`,
`solarized`, `firewatch`, `mutedEarth`, `hokusaiMist`, and `harborDusk`.
`experiment` intentionally remains an uncolored customization base, matching
its currently unspecified palette, while `plain` is the explicit stable
no-ANSI preset. Each preset and its colors must be declared in one
`ThemeDefinition`; positional arrays keyed implicitly by enum order are not
allowed.

`StackTraceStyle.moduleDisplay` defaults to `ModuleDisplay.omitted`. Rendering
removes lowercase package/module prefixes while retaining aggregate ownership,
so `examples.app.SceneLoader.load(ref xtb.core.Context)` is displayed as
`SceneLoader.load(ref Context)`. Demangling itself always retains the complete
qualified name. D linkage names do not encode the boundary between modules and
enclosing aggregates, so omission deliberately follows the idiomatic D naming
convention: lowercase qualifiers are modules and uppercase qualifiers are
types. Projects using lowercase aggregate names or uppercase module names must
select `ModuleDisplay.full`. Use that mode whenever exact qualification matters.

Fatal diagnostics require explicit process startup:

```d
scope CrashHandlerScope crashes = CrashHandlerScope.install(argv[0]);
```

There are no module constructors. Installation is process-global, must happen
before application worker threads start, and a second simultaneous scope is a
programming error. Scope destruction restores the previous panic and signal
handlers. A panic occurs in ordinary execution context, so its hook may use
libbacktrace and the complete styled renderer before `abort` terminates the
process.

Signal installation is transactional: if installing any handler fails, every
handler installed earlier in that attempt is restored before the installation
panic is raised.

Linux fatal-signal handling has a stricter contract. `write`, `_exit`, and the
signal metadata path are async-signal-safe; libbacktrace, allocation, stdio,
logging, locks, and general symbolization are not.
`SignalTraceMode.faultAddressOnly` therefore prints the faulting program
counter from `ucontext` and stops. `SignalTraceMode.attemptStackUnwind`, the
ergonomic default, additionally invokes the platform stack
unwinder after warming it during installation. It often produces useful raw
program counters but cannot be guaranteed deadlock-free after arbitrary memory
corruption. This tradeoff is explicit in the mode type. Signal output never
calls the D demangler, allocator, logger, `Writer`, or libc buffered I/O.

The fatal-signal backend is compiled only under `version (linux)`. Other
platforms retain the same explicit `CrashHandlerScope` and panic-hook API, but
do not install signal handlers until a platform backend with locally verified
context and unwinding support exists. This keeps the portable BetterC library
buildable instead of importing Linux facilities under a broad POSIX guard.

After reporting, the handler restores normal fatal-signal semantics by
re-delivering the original signal. This preserves the conventional exit status
and core-dump behavior. Handle only crash signals (`SIGABRT`, `SIGBUS`,
`SIGFPE`, `SIGILL`, and `SIGSEGV`); do not reinterpret interactive or orderly
termination signals as crashes.

### Memory and ownership

Allocation is a dependency. Preserve the useful shape of the C++ allocator:
`Allocator` is a single realloc-style function-pointer type, while the handle
passed through APIs is `Allocator*`--a pointer to that function-pointer slot.
The callback uses C linkage so an allocator slot can safely cross the C ABI.
Calling the allocator dereferences the slot and passes the handle itself back
as the callback's opaque first argument. It is not a two-word
`{ function, context }` pair.

Conceptually, the operation is:

```d
alias Allocator = extern(C) void* function(
    void* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
) nothrow @nogc;

void* reallocate(
    Allocator* allocator,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
) @system nothrow @nogc
{
    return (*allocator)(allocator, newSize, oldPointer, oldSize, alignment);
}
```

A stateless allocator can expose a standalone function-pointer slot. A
stateful allocator embeds that slot as the first field of its state struct and
exposes it consistently through a mutable `Allocator* allocator()` member. For
example, `arena.allocator` returns the address of Arena's private allocator
slot, and the callback casts that opaque address back to `Arena*`. The same
member name is used by `InstrumentedAllocator`, temporary/scratch arenas, and
other allocator adapters. This intrusive convention keeps the public handle to
one pointer, but it depends on an explicit layout invariant. Enforce that
invariant with a static assertion on the private slot's offset, keep the
callback signature identical, and never move or copy the state while its
allocator handle is in use.

An operation that retains or returns owned memory receives `Allocator*`
explicitly or uses an owning object that already stores that handle. Document
how long the allocator slot and its containing state must remain alive. Do not
introduce a mutable global "current allocator."

The typed allocator API distinguishes single objects, arrays, storage
initialization, and object lifetime deliberately:

```d
T* value = allocator.allocate!T();                 // raw storage for one T
T[] values = allocator.allocateArray!T(count);     // raw storage for count T

T* zeroed = allocator.allocateZeroed!T();
T[] zeroedValues = allocator.allocateZeroedArray!T(count);

T* initialized = allocator.allocateInit!T();       // establishes T.init
T[] initializedValues = allocator.allocateInitArray!T(count);

T* constructed = allocator.create!T(arguments);    // allocate + emplace

allocator.deallocate(value);                       // raw storage only
allocator.deallocateArray(values);                 // raw storage only
allocator.dispose(constructed);                    // destroy + deallocate
allocator.disposeArray(initializedValues);          // destroy all + deallocate
```

Every allocating operation has a `try` variant where allocation failure is a
normal result. `allocate!T` never accepts an element count: arrays use the
slice-returning `allocateArray!T` API so their length is not immediately lost.
POD array reallocation likewise uses `reallocateArray`, which receives and
returns slices.

Zeroed allocation is restricted to POD representations. Zeroed allocation
means every byte is zero and is intentionally distinct from `T.init`.
`allocateInit` and `allocateInitArray` establish normal D initialization with
`emplace`; `create` additionally forwards constructor or source-value arguments
to `emplace`. Raw `deallocate` functions never run destructors. Use `dispose`
for an initialized single object and `disposeArray` for an initialized array
when the allocation came from a general allocator.

`Arena` mirrors the single/array, zeroed, initialized, and `create` allocation
vocabulary because those operations are useful for arena-backed graphs and
ASTs. It intentionally has no per-allocation `deallocate`, `dispose`, or
reallocation member. `Arena.clear()` and `Arena.deinit()` reclaim storage in
bulk and **do not run destructors for values constructed in the arena**. Code
that places resource-owning objects in an arena must arrange any required
cleanup separately before rewind or destruction.

Use these representations consistently:

- `T[]`/`const(T)[]`: borrowed slice; document lifetime and mutability.
- `T*`: mutable caller-owned object, optional object, opaque handle, or
  explicitly owned allocation; document which one and whether null is valid.
- owning `struct`: stores the allocator/resource handle, offers `deinit`, and
  is either non-copyable or has clearly named move/clone operations.
- arena/scratch allocation: request-scoped data with an explicit checkpoint
  and rewind. Values backed by scratch memory must not escape that scope.

Prefer a useful zero state. `deinit` should tolerate it and leave the value
zeroed so accidental double cleanup is harmless where the resource permits.
Do not rely on postblits, hidden heap allocation, array concatenation/appending,
closures that allocate, or Phobos templates without confirming their BetterC
link behavior.

### Strings

The string model has three deliberately separate types: `String` is a
read-only borrowed view, `StringBuf` is an owning mutable growable buffer, and
`OwnedString` is an owning immutable exact-sized value. Do not collapse these
roles and do not use a mutable D slice as the public string abstraction.

#### `String`: read-only borrowed text

Use D's native slice representation rather than recreating pointer and length
accessors in a wrapper struct:

```d
alias String = const(char)[];
```

The alias is declared in the dependency-free `xtb.core.types` module and
publicly re-exported by `xtb.core.string`. It cannot contain member functions;
the string algorithms are free functions deliberately designed for UFCS, so
`text.trimAscii()` retains member-like call syntax without wrapping the native
slice or weakening literal interoperability.

`String` does not own, allocate, reallocate, free, or mutate its storage.
Constness prevents user code from modifying bytes through the view. Copying it
copies only its pointer and length; its bytes must outlive every copied or
derived view. It is a simple, trivially copyable value with no destructor or
hidden state. A substring, trim, prefix, suffix, split token, or other operation
that can reuse existing bytes returns another `String` without allocation.
Use project free functions for equality, comparison, searching, hashing, and
transformation, invoked through UFCS (`text.trimAscii()`, `text.find(needle)`). Do
not assume a built-in array operation is BetterC-safe until its link behavior
has been verified by the BetterC tests.

`String` is mandatory everywhere an API handles string data without intending
to mutate the bytes. Ordinary modules do not spell `const(char)[]`, D `string`,
or `const(char)*` in place of it. Raw pointers are confined to C boundaries,
and mutable slices are confined to `StringBuf` internals. This consistency is
what makes ownership and mutation obvious across the library.

Operations that create different bytes--concatenation, replacement, escaping,
case conversion, formatting, and joining--must either receive an explicit
allocator and return a `String` into storage owned by that allocator, or
write into/return a `StringBuf`. They must never make `String` itself
appear to own the allocation. The caller chooses the form based on whether
allocator-scoped lifetime or individually managed ownership is required.

String literals and immutable static storage can be viewed for the entire
program. A `String` made from a `StringBuf`, scratch allocation, mapped
file, or foreign buffer inherits that source's shorter lifetime. APIs retaining
a string beyond the call must copy it into their own `StringBuf` or
persistent allocator; accepting `String` never implies permission to
retain it.

Do not use D's built-in `string` alias as the general view type. `string` is
`immutable(char)[]`, which promises the bytes can never change through any
alias. That promise is valid for literals and genuinely frozen storage, but not
for a temporary view into a mutable `StringBuf`. Converting such storage to
`string` would require an unsafe cast and would become incorrect as soon as the
buffer changed. `const(char)[]` provides the required read-only access without
making a false global-immutability guarantee.

The zero value is the valid empty string. Expected failure is represented by a
`Result`/status, not an "invalid string" sentinel encoded as a special pointer.
Embedded NUL bytes are allowed and `length` never includes an optional C
terminator.

Strings are byte-addressed valid UTF-8 by contract. `String.length` and
`byteLength` count bytes, indexing yields a UTF-8 code unit, and built-in D
slicing is unchecked. Use `sliceBytes`, `prefixBytes`, and `suffixBytes` for
boundary-checked views. Unicode scalar traversal is explicit through
`codePoints`, `codePointsWithOffsets`, and `codePointCount`; none of these APIs
claim to count grapheme clusters. The alias cannot enforce validity, so foreign
bytes enter through checked `asString`/`fromCString` or a visibly `@system`
unchecked conversion whose caller already owns the proof.

Binary data crosses into the string API only through visibly unchecked
boundaries:

```d
String borrowed = bytes.asStringUnchecked();
StringBuf owned = StringBuf.fromBytesUnchecked(allocator, bytes);
```

`asStringUnchecked` performs no allocation or UTF-8 validation and returns a
read-only view with the source slice's lifetime. Mutation through a different
alias remains observable. `fromBytesUnchecked` copies already-proven UTF-8 into
independent owned storage; its `tryFromBytesUnchecked` counterpart reports
allocation failure. Embedded NUL is valid and preserved, but malformed UTF-8
violates both unchecked functions' preconditions. Binary ownership uses
`Array!u8`. Do not scatter equivalent casts through user code.

#### `StringBuf`: owned mutable storage

`StringBuf` owns a growable byte allocation and stores its `Allocator*`, data
pointer, logical length, and capacity. It is non-copyable, has a useful empty
zero state, and releases its allocation in `deinit`/RAII cleanup according to
the allocator contract. Ownership transfer, if needed, uses an explicitly
named move/release operation that leaves the source empty; ordinary assignment
must not duplicate ownership.

The zero state may be queried, cleared, moved, or destroyed, but it has no
allocator and therefore cannot grow. Fallible growth returns `false`; panicking
growth reports the missing allocator. Construct it with `create`,
`withCapacity`, or `fromString` before appending.

All `StringBuf` receiver-owned operations are handwritten members. The bound
allocator is injected by those methods into `StringBufUnmanaged`; other mutable
outputs remain explicit pointers. This gives code-d/serve-d a concrete member
declaration to navigate instead of requiring it to reconstruct a large UFCS
overload set through aggregate re-exports.

```d
StringBuf buffer = StringBuf.create(allocator);
buffer.append(prefix);
StringBuf* pointer = &buffer;
pointer.append(':');
buffer.append(value);
String result = buffer.view;
```

The same rule applies to `Array!T`, `HashMap`, `HashSet`, `OwnedString`, the
string hash containers, and future managed containers. Their structs contain
ownership fields, static factories, ordinary member operations, one
mutable-only `Allocator* allocator()` member, and D-required hooks such as a
destructor, indexing, equality, or `foreach`. D's normal struct-pointer member
lookup makes duplicate pointer forwarding overloads unnecessary. In checked
builds a version-gated invariant rejects a null receiver; release-fast removes
that contract entirely. Reserve, resize, append, prepend, insert,
replace-in-place, clear, and formatting operations validate overflow before
changing the buffer. On a recoverable allocation failure the original contents
remain valid unless the operation documents otherwise. The full handwritten
pattern is documented in `docs/managed-containers.md`.

`view()` returns a read-only `String` borrowing the current contents. Any
operation that can reallocate, shift, overwrite, clear, release, or destroy the
buffer invalidates affected views. The type system must not offer an implicit
conversion that hides this borrowing relationship. To preserve text after the
buffer changes or dies, initialize a different `StringBuf` from the view
using the destination allocator.

Use `==` and `!=` for ordinary content comparisons. `String` receives D's
built-in slice equality, while `StringBuf` overloads equality against both
`String` and another `StringBuf`. Mixed equality is symmetric, so both
`buffer == "text"` and `"text" == buffer` are valid. Every form compares the
exact bytes and length without allocating; it does not normalize or transcode
Unicode. A null `String` and an empty `StringBuf` compare equal because both
represent the same zero-length byte sequence. `StringBuf.equal` remains available as an explicit member comparison, but do
not create a borrowed view merely to compare an owned buffer. `StringBuf.toHash` hashes those same bytes and therefore stays
consistent with equality. Since mutation changes the hash, never mutate a
buffer while an external hash table is using its contents as a key.

Copying a `String` into owned storage is explicit:

```d
StringBuf owned = StringBuf.fromString(allocator, input);
```

Builder-style utilities that are genuinely external algorithms may still take
`ref StringBuf output` when composition or allocation reuse matters. Ordinary
buffer operations themselves are members. Convenience functions may return
`StringBuf` by move. Utilities returning an allocator-backed `String` document
that the allocator, not the view, owns its bytes and when those bytes become
invalid.

`formatString` returns a `StringBuf`, not an owning-looking `String` view. It
formats directly into that builder in one pass, so a custom `formatTo` function
is invoked exactly once. `tryFormatString` leaves a zero `StringBuf` on
allocation or sink failure.

#### `OwnedString`: owned immutable exact storage

`OwnedString` owns valid UTF-8 bytes whose allocation is exactly the logical
byte length. It stores one allocator pointer plus `OwnedStringUnmanaged`; the
unmanaged representation is exactly one `String`-sized pointer-and-length
owner with allocator-explicit cleanup. Neither type stores capacity or a
trailing NUL byte, and neither exposes mutable byte access.

Use `OwnedString` for independently owned text that will not be edited, such as
persistent names and values. Construction from a borrowed `String` copies
exactly once. `clone` is explicit because it allocates. Copying is disabled;
move, `release`, `adopt`, and `ReleasedStorage` preserve allocator provenance.
Empty managed values created through a factory remain bound to their allocator,
just like other managed containers.

Conversion from `StringBuf` is transactional. A same-allocator buffer with
exact capacity transfers its allocation directly; spare capacity is first
shrunk when possible. A foreign-allocator buffer is copied into the destination
allocator and released only after the copy succeeds. On recoverable failure the
source and output remain unchanged.

`OwnedString.view` returns a borrowed `String`. Embedded NUL participates in
length, equality, and hashing. Callers needing a conventional C string copy the
view into `StringBuf` and call `checkedCString`; immutable exact storage does
not reserve terminator capacity.

#### Formatting and interpolation

Prefer D interpolated expression sequences for readable, type-safe local
formatting:

```d
writeln(i"loaded $(count) records from $(path)");
buffer.formatTo(i"address=$(hexadecimal(address)), ratio=$(fixed(ratio, 3))");
StringBuf owned = formatString(allocator, i"$(name): $(value)");
```

An `i"..."` expression is not a `String` and must not be stored as one. At a
function call it expands into compile-time literal/expression markers and the
already-evaluated expression values. The printer writes literal marker text,
ignores the header, footer, and expression-source metadata, and sends each
value through the ordinary `formatTo` dispatch. It never parses or evaluates
the source text stored in an expression marker. Consequently expressions are
evaluated exactly once by D, nested interpolated sequences compose naturally,
and interpolation itself requires neither a runtime format parser nor an
allocation.

`write`, `writeln`, `ewrite`, `ewriteln`, `writeFile`, `writelnFile`,
`StringBuf.writeTo`, and `writeBuffer` accept interpolated sequences directly.
The `format`, `formatln`, `StringBuf.formatTo`, `formatBuffer`, `formatString`,
and `tryFormatString` overloads do as well. A fixed-buffer result reports the
same written, required, and truncation values regardless of whether its input
uses interpolation or ordinary arguments. An owned result always requires an
explicit allocator.

Formatting policy stays explicit in expressions. Use wrappers such as
`hexadecimal(value)`, `.digits(width)`, `fixed(value, precision)`, and custom
values implementing `formatTo(ref Writer)`; do not add a second formatting
mini-language inside the interpolation text. Keep the compile-time
`formatln!"...{}..."` family for call sites where positional placeholders are
clearer or an existing format string is already the natural representation.

#### C strings and termination

`String` is not NUL-terminated by contract and must never be passed
directly to a C API expecting `const char*`. A C-boundary helper copies into a
`StringBuf`--normally scratch-backed--and then calls `cString` or
`checkedCString`. These operations write one terminator outside the logical
length; `StringBuf` does not maintain it after every mutation. The NUL is not
part of `view()`, equality, hashing, or iteration. `checkedCString` rejects
embedded NUL when the target C API would otherwise truncate the value.

A pointer returned for C interop is valid only until the buffer is mutated or
its owner/scratch scope ends. It must not escape unless the foreign API
explicitly copies the string. Never cast away constness to avoid this
conversion.

#### API rules

- Accept `String` by value for read-only string input.
- Put ordinary `StringBuf` container mutation on member methods. Independent
  builder-style utilities may accept `ref StringBuf output`; use pointers for
  additional mutable outputs.
- Return `String` for borrowed views or read-only results whose storage is
  owned by an explicit allocator; return `StringBuf` for individually owned
  mutable text.
- Require an explicit allocator for every operation that may create storage.
- Document the owner/lifetime of every returned view.
- Keep byte length and capacity in `size_t`; check all additions and growth.
- Define equality and hashing over exactly `length` bytes, including embedded
  NUL bytes.
- Do not expose the buffer's mutable storage through a `String` API.
- Do not use GC strings, concatenation with `~`, or implicit allocation.
- Use the `String` alias in every non-mutating string API; spelling its
  underlying slice type directly is reserved for its declaration and low-level
  implementation work.

### Scratch space

Scratch space is the standard allocator for temporary work buffers. It is not
an incidental arena feature: parsers, formatting, path conversion, geometry
processing, and foreign-API adapters should use it instead of repeatedly
allocating from a general-purpose heap.

Each thread that needs scratch explicitly creates a `ThreadContextScope` at its
entry point. That RAII scope owns a configurable collection of reusable arenas
and installs a pointer to its `ThreadContext` in compiler/platform TLS. Its
destructor clears the TLS pointer and releases the context. Threads that do not
need these facilities create no context and pay no initialization cost.

Scratch APIs obtain the current context from TLS; they do not receive an
explicit pool or context parameter. This is the intentional exception to the
general rule against hidden allocator selection. There is still no implicit
runtime initialization, module constructor, or process-global scratch pool:
the thread must have explicitly installed its context first.

Beginning a scratch scope does three things:

1. Select an arena whose allocator handle is absent from the caller's conflict
   list.
2. Save a checkpoint containing the arena's current chunk and offset.
3. Return a scope value exposing `Allocator*` for temporary allocations.

Ending the scope rewinds exactly to that checkpoint. Scratch scopes over one
arena are strictly LIFO. Rewind invalidates every pointer, slice, and allocator-
backed object created after the checkpoint; it does not run destructors or
individual cleanup callbacks. Scratch storage is therefore limited to plain
temporary data and objects whose external resources are released explicitly
before rewind.

The arena layer exposes the same mechanism independently of RAII. `push`
captures an arena checkpoint in a `TempArena`; `pop` rewinds it and marks the
value inactive:

```d
struct TempArena
{
    Arena* arena;
    ArenaCheckpoint checkpoint;
    bool active;

    @disable this(this);
}

TempArena push(Arena* arena) nothrow @nogc;
void pop(ref TempArena temporary) nothrow @nogc;
```

The functions are UFCS-oriented:

```d
Arena* arena = scratchArena(outputAllocator); // panics if none is available
TempArena temporary = arena.push();

// Temporary allocations...

temporary.pop();
```

This manual API is required for low-level control flow where an RAII guard
cannot express the desired lifetime. The caller must execute exactly one
`pop` on every normal path. Popping an inactive value, popping out of LIFO
order, using the wrong thread, or popping after its arena/context has been
released is a contract violation and panics. `TempArena` is non-copyable so a
checkpoint cannot acquire two apparent owners.

The D interface uses RAII for the lifetime, conceptually:

```d
struct ScratchScope
{
    private TempArena temporary;

    @disable this(this);

    private this(scope Allocator*[] conflicts) nothrow @nogc
    {
        ThreadContext* context = currentThreadContext();
        if (context is null)
            panic("scratch requested without a thread context");

        Arena* arena = context.selectNonConflictingArena(conflicts);
        if (arena is null)
            panic("no non-conflicting scratch arena");
        temporary = arena.push();
    }

    ~this() nothrow @nogc
    {
        temporary.pop();
    }

    static ScratchScope acquire() nothrow @nogc;
    static ScratchScope acquire(Allocator* conflict) nothrow @nogc;
    static ScratchScope acquire(scope Allocator*[] conflicts) nothrow @nogc;

    Allocator* allocator() nothrow @nogc
    {
        return &temporary.arena.allocator;
    }
}
```

`ScratchScope` is a non-copyable stack-owned RAII guard. Its destructor rewinds
the checkpoint automatically at every normal lexical exit, including early
returns. Callers must not add a parallel `scope(exit)` cleanup or call rewind
manually on a scope-owned `TempArena`. Its destructor is implemented through
the same lower-level `pop` operation rather than a separate rewind path.
Scratch acquisition is deliberately infallible at the API level: a
missing thread context or failure to find a non-conflicting arena is a violated
runtime precondition. Checked builds immediately call the project's panic
handler; release-fast assumes the precondition. There is no status result,
nullable scratch value, or recovery branch in callers.

D structs do not provide a user-defined parameterless default constructor, so
the zero-conflict form uses the named `ScratchScope.acquire()` factory. The
single-conflict overload is the normal nested form, and the slice overload
preserves the many-conflict API for contexts configured with additional
arenas. All three produce the same non-copyable RAII guard. The factory/return
path must use D's move or copy-elision behavior and must never duplicate an
active guard.

Conflict tracking protects live allocations. If a function receives an
allocator that may own its inputs or outputs and also needs scratch memory, it
passes that allocator in the conflict list. This prevents selection of the
same arena and prevents the nested scratch rewind from invalidating caller-
owned results. Conflicts compare allocator-handle identity (`Allocator*`), not
callback-function equality: several arenas may use the same callback.

```d
String makePath(
    Allocator* outputAllocator,
    scope String left,
    scope String right,
) nothrow @nogc
{
    ScratchScope scratch = ScratchScope.acquire(outputAllocator);

    StringBuf temporary = StringBuf.create(scratch.allocator);
    temporary.append(left);
    temporary.append('/');
    temporary.append(right);

    // copy allocates the returned bytes from outputAllocator. They therefore
    // remain valid after scratch's destructor rewinds its temporary arena.
    return temporary.view().copy(outputAllocator);
}
```

`outputAllocator` is passed as the single conflict because the returned
`String` is backed by it. If the scratch scope selected that same arena, its
destructor would rewind and invalidate the result before the caller could use
it.

The many-conflict list construction must itself remain allocation-free; a
small static array or caller-provided slice is sufficient. Conflicts are
passed only when live allocations from those allocators must survive the new
scope.

Constructing a second `ThreadContextScope` on the same thread, destroying it
out of order, or requesting scratch without an installed context panics. This
mirrors the useful behavior of the C++ `ThreadContextScope` and `ScratchScope`
while keeping thread initialization explicit.

Arena growth belongs to the thread context and uses its explicitly configured
backing allocator. Rewind should normally retain chunks for reuse, subject to a
documented high-water or trimming policy; it must not make an ordinary scratch
scope pay heap allocation on every invocation. Alignment is honored for every
request, size arithmetic is overflow-checked, and allocation failure is
reported through the allocator contract. An opt-in diagnostic build may poison
rewound bytes and tag checkpoints/generations to help expose use-after-rewind,
double-end, non-LIFO release, and a scratch scope used from the wrong thread;
these diagnostics are not required behavior of an ordinary debug build.

Scratch lifetime rules are absolute:

- Never return or retain scratch-backed memory past the scope.
- Never store a scratch allocator handle in a longer-lived object.
- Never copy a `ScratchScope`, invoke its destructor manually, or separately
  schedule its rewind with `scope(exit)`.
- Never copy a `TempArena`; when using the manual API, pair each successful
  `push` with exactly one LIFO `pop` on every normal path.
- Never use scratch for persistent cache, renderer, window, or GPU-resource
  state.
- Never rewind an arena while a nested scope on that arena is active.
- Never pass a scratch-backed input to a nested operation without listing its
  allocator as a conflict when that operation may acquire scratch.
- Copy the final result into the caller's explicit allocator before ending the
  scope.

### Errors, contracts, and safety

Expected errors use values: a compact `Result!(T, E)`, status enum plus output
parameter, or byte-count/sentinel where that convention is unambiguous. Errors
carry stable machine-readable categories; optional diagnostic text is written
into caller-provided storage. Assertions are reserved for programmer errors
and internal invariants. There are no exceptions.

Mark code with the strongest truthful attributes. Public leaf functions should
normally be `@safe`, `nothrow`, and `@nogc`; `pure` is valuable for algorithms.
Pointer arithmetic, unions, C variadics, and foreign calls belong in small
reviewable `@system` adapters. A safe wrapper validates lengths, ranges, enum
values, nullability, and integer overflow before entering such an adapter.

## Structured serialization

`xtb.serde` is a schema-driven object mapper, not a general JSON or TOML DOM.
It serializes concrete BetterC values by inspecting their fields at compile
time and deserializes directly into the requested type. Runtime reflection,
`TypeInfo`, registration, built-in D associative arrays, exceptions, and hidden
GC allocation are forbidden. The allocator-owned `HashMap` is supported
explicitly instead. Backends share schema and ownership machinery but do not
share a text-shaped intermediate representation; a future binary backend can
therefore preserve field identifiers, fixed-width values, and other binary
policies without pretending they are strings.

Schemas support booleans, signed and unsigned integers, floating-point values,
enums, nested structs, fixed arrays, `Option!T`, borrowed
`StringViewHashMap!V`/`HashMap!(String, V)`, and owning `StringHashMap!V`, plus
two deliberate ownership families. Document-owned schemas use `String`,
dynamic slices, legacy nullable pointers, and borrowed string-view maps whose
values recursively follow the same document-owned model. Self-owning schemas
use `StringBuf`, `OwnedString`, `Array!T`, and `StringHashMap!V`; they do not
contain raw owning pointers, borrowed slices, or borrowed-key maps.
`Option!T` is the preferred nullable representation in either family and
recursively adopts the ownership model of `T`. JSON accepts any supported value
at the document root. TOML remains a table document, so its root is a serde
struct, tagged union, `HashMap!(String, V)`, or `StringHashMap!V`; standalone
arrays and scalars are rejected at compile time. Unsupported or mixed
ownership shapes fail at compile time with the field and type in the diagnostic.

Enums use their D member names in text formats by default. `@variantCase`
sets an enum's external casing independently of field-key casing. `@rename`
on an enum member replaces its encoded spelling, and repeated `@aliasName`
attributes preserve decode compatibility with former spellings. Explicit
renames and aliases are exact and are never case-transformed. Empty or
overlapping member names and aliases are compile-time schema errors.

`Option!T` is an ordinary BetterC value. `Option.init` is absent; `isSome` and
`isNone` are the state queries used by ordinary option code. Boolean conversion
tests presence. `empty` is an alias for `isNone` provided only for compatibility
with range-oriented generic code; do not use it when directly inspecting an
option. Construction and replacement are explicit: use `some(value)` for presence and
`none()` for absence. Raw `T` values do not implicitly construct or assign an
Option. `reset` is the equivalent direct mutating operation for returning an
existing Option to absence, and `take` transfers the current value out.
`unwrap` is the always-checked consuming form of `take`: absence panics even in
release-fast builds. `expect(message)` has the same behavior with a
caller-provided panic message. Access through `value` checks that it is present,
and `value`/`pointer` propagate mutable, const, and
immutable qualifiers with `inout`. The option always contains valid `T.init`
storage, which lets compiler-generated destruction handle owning `T` without a
manually managed union. It is copyable exactly when `T` is copyable and is
`@mustuse`. `OptionReturns` introduces return-type-specific `some` and `none`
aliases. Every non-constructor function with an explicit `Option!T` return type
uses that mixin and constructs its returns through those aliases. The free UFCS
`map`, `andThen`, and `orElse` algorithms infer their transformed return types
and therefore construct through their computed type aliases instead. This
keeps alias lambdas out of BetterC-incompatible dual-context member closures.
JSON encodes an absent option as `null` and accepts `null`; TOML has no null
value, so it omits absent option fields and makes an option present whenever its
key is decoded. A missing field remains absent. `@required Option!T` requires
the key to occur; in JSON, an explicitly present `null` still satisfies that
key-presence rule while leaving the option absent.

`Result!(T, E)` is the corresponding BetterC error-flow value. It has explicit
`ok` and `err` variants plus a valid empty state used by `Result.init` and by a
result after `take`/`takeError`. Boolean conversion means `isOk`; callers use
`isErr` or `isEmpty` when those states matter explicitly. Both payload slots
remain valid initialized D values, avoiding a manually managed union and making
normal destruction reliable for owning payloads. Copyability follows both
payload types, and Result is `@mustuse`. `unwrap`/`expect` consume a success
payload and panic unless the result is ok; `unwrapError`/`expectError` do the
symmetric operation for errors. Those checks are unconditional and remain
enabled in release-fast builds. `Result!(void, E)` represents success without
a success payload; its `unwrap`/`expect` consume the successful state.

Every non-constructor function with an explicit `Result!(T, E)` return type uses
`mixin ResultReturns;`, which aliases `ok` and `err` to that function's exact
return type. The generic transformation algorithms infer a computed Result type
and construct through that type alias instead. In addition to constructing an
error from `E`, `err(otherResult)` consumes the error of a `Result!(U, E)` and
rebinds it to the enclosing success type. Thus ordinary propagation is:

```d
auto value = operation();
if (!value)
    return err(value);
return ok(value.take());
```

`map`, `mapError`, `andThen`, and `orElse` are free UFCS algorithms rather than
member templates. This is deliberate: LDC requires a dual context when an alias
lambda and a member-template receiver both carry context, which can require a
GC closure under `-betterC`. Free UFCS functions preserve fluent call syntax
without that restriction. They consume their wrapper argument by value: a
temporary flows naturally, copyable lvalues follow normal D value semantics,
and non-copyable lvalues require an explicit `move`. Result is not mandated as
the representation for every fallible API. Explicit status-plus-out-parameter
interfaces remain appropriate where they make ownership, partial output, ABI,
or hot-path behavior clearer.

Fields use narrowly scoped UDAs from `xtb.serde.attributes`:

- `@rename("wire_name")` changes the serialized key;
- repeated `@aliasName("old_name")` values add decode-only legacy keys;
- `@ignore` excludes a field in both directions;
- `@required` rejects input that omits the field;
- `@defaultValue(value)` supplies a missing field's explicit decode default;
- `@omitDefault` suppresses the field initializer or explicit
  `@defaultValue` while encoding;
- `@omitIf!predicate` suppresses a field when its accessible, allocation-free
  predicate returns true;
- `@withSerde!Adapter` maps one field through a user-defined scalar
  representation; and
- `@flatten` merges a nested struct's fields into its parent map.

Key spelling is controlled independently of field selection. `KeyCase`
supports preserve, camel, Pascal, snake, screaming-snake, and kebab casing. A
struct-level `@fieldCase(...)` declares its normal external convention, while
a backend option can override casing for a whole document. Word splitting
handles ordinary camel case, existing separators, and acronym boundaries such
as `HTTPServerID` -> `http_server_id`. An explicit `@rename` and every
decode-only alias are exact wire spellings and are never transformed again.

Names and aliases must be nonempty and unique after flattening. `@ignore`
cannot be combined with another serde UDA, and `@flatten` is valid only for a
non-pointer struct field. These are compile-time schema errors. Unknown input
keys and duplicate assignments are rejected by default; options may ignore
unknown keys for forward compatibility, but never silently accept duplicate
keys. Missing fields retain the D field initializer unless `@defaultValue`
overrides it or `@required` rejects the omission. `@omitIf` and
`@omitDefault` are mutually exclusive.

A serde adapter is an explicit exception to structural reflection. It must
declare `Representation` as `String`, a boolean, a number, or an enum and
provide these operations:

```d
static SerdeErrorKind encode(
    scope const ref Value value,
    Representation* output,
);

static SerdeErrorKind decode(
    scope const ref Representation value,
    Allocator* allocator,
    Value* output,
);
```

Adapters are appropriate for opaque identifiers, validated units, timestamps,
and other values whose wire form must not mirror their fields. They return
errors explicitly and receive the decode allocator; they do not write JSON or
TOML themselves. The representation is borrowed only for the duration of the
call and must not be retained; an adapter that needs persistent storage uses
the supplied allocator explicitly. This keeps the adapter reusable across backends. Structural
adapter representations are deliberately deferred until a format-neutral
streaming value interface is justified.

### Tagged unions

A tagged union is a struct annotated with `@taggedUnion(layout)`. It contains
exactly one enum field marked `@discriminant` and one D union field marked
`@payload`. Every payload member uses `@caseOf(Enum.member)`. The markers bind
the actual D fields: `@rename` and casing can change their external names
without changing which fields control the union.

Three layouts are supported:

```text
external: { "created": { "id": 7 } }
internal: { "event_type": "created", "id": 7 }
adjacent: { "event_type": "created", "event_data": { "id": 7 } }
```

External tagging accepts every supported case value. Internal tagging requires
ordinary struct cases because their fields are merged beside the tag. Adjacent
tagging preserves a separate payload value. Decoders accept the discriminant
before or after payload fields and diagnose absent tags, duplicate tags,
unknown variants, name collisions, incomplete case mappings, and duplicate
discriminant values. Untagged trial decoding is not supported: it is ambiguous,
has poor failure diagnostics, and requires speculative parsing.

Raw D unions do not destroy only their active member. Consequently the current
tagged-union schema accepts document-owned borrowed cases and rejects direct
self-owning cases at compile time. A future `SumType` may provide active-member
construction and destruction while implementing this same schema contract;
serde does not require such a container today.

JSON and TOML both support all three layouts at document roots and as nested
values. TOML uses inline tables for nested tagged values and ordinary root
assignments for root tagged documents.

Binary byte-string values, numeric field identifiers, and automatic schema
version comparison are not part of the current model. If binary values are
added later they must be distinct from `String` and must specify each text
backend's encoding explicitly rather than silently treating arbitrary bytes as
UTF-8.

Schema evolution is a documented compatibility contract, not runtime
migration machinery. Adding defaulted data remains decodable by new readers;
adding required data is breaking; renames retain compatibility through
decode-only aliases; removed fields require an intentional unknown-field
policy; and removing or respelling variants requires an explicit fallback or
alias. The library does not compare two compiled schema revisions and claim
that arbitrary source edits are compatible.

Text decoding offers two lifetime models. A document-owned decode writes a
`Deserialized!T`, a non-copyable RAII owner holding both `T*` and an internal
allocation tracker over its explicit `Allocator*`. The tracker records only
allocations made by that decode, so destruction and partial-failure cleanup do
not mistake a static field initializer or other default pointer for owned
memory. Its destructor releases the exact allocation set made by the backend;
the output remains empty on failure. A `String` inside the result is still a
read-only simple view, but newly decoded bytes are owned by the surrounding
`Deserialized!T`. `HashMap!(String, V)` belongs to this model as well: object or
table keys are copied into tracked storage, while the map's buckets and nested
values use the same tracking allocator. A view, pointer, or map obtained from
the result expires when that owner is reset or destroyed.

A self-owning decode writes an ordinary caller-owned value directly. JSON root
values may be scalars, `StringBuf`, `OwnedString`, fixed arrays, `Array!T`,
`StringHashMap!V`, or structs composed from those shapes. TOML direct roots
remain serde structs, tagged unions, or `StringHashMap!V` table documents.
Each container uses the allocator passed to `readJson` or `readToml`; no
tracking allocator or result wrapper is involved. Decoding is transactional:
the backend builds a temporary RAII value, destroys it on any failure, and
replaces the caller's previous output by move only after the whole document
succeeds. The previous value therefore remains intact on syntax, schema, range,
limit, or allocation failure. The resulting value can be mutated, moved,
reset, and extended using the normal `StringBuf` and `Array!T` APIs. Every
direct owning container in a successful result is initialized with the decode
allocator even when its field was absent, including containers inside nested
records and fixed or dynamic owning arrays. `StringViewHashMap`/
`HashMap!(String, V)` is intentionally absent from direct decoding because its
stored `String` keys are borrowed views. `StringHashMap`
qualifies only when its value type is recursively self-owning.
An absent `Option!T` is made present by assigning a value before its value is
accessed.

Serde permits compiler-generated destruction arising from supported owning
fields. A user-defined destructor remains unsupported because the decoder
cannot infer its construction invariants or whether partially initialized
state is valid; such types require a future explicit adapter.

Serialization writes to `Writer` and performs no allocation. Deserialization
accepts a `String` input, explicit allocator, explicit output pointer, and
limits for nesting and collection sizes. Expected problems return
`SerdeError`, including a stable category plus byte offset and text
line/column. Syntax errors, range errors, invalid UTF-8/escapes, unknown or
duplicate fields, missing required fields, depth exhaustion, and allocation
failure are recoverable results rather than panics. Null required pointers and
invalid option contracts remain programmer errors. An unknown tagged-union
discriminant reports `unknownVariant`, independently of an unknown map key.

The JSON backend emits and accepts strict UTF-8 JSON: no comments, trailing
commas, non-finite floats, invalid surrogate pairs, or duplicate object keys.
A `HashMap!(String, V)` maps directly to a JSON object, including at the document
root. Pretty printing is policy only and never changes the data model. The TOML
backend's deterministic encoding uses inline tables for nested structs and hash
maps, arrays of inline tables for struct collections, and ordinary key/value
assignments for a root hash map. Scalar arrays use TOML arrays. Static struct
schemas additionally decode dotted keys and ordinary `[table]` headers; dynamic
hash-map keys are accepted as root assignments or inline-table entries, with a
quoted key preserving dots literally. Basic and literal single-line strings,
booleans, integers, floats, arrays, and inline tables comprise the supported
TOML value model. Multiline strings, date/time values, dynamic map table
headers, and `[[array-of-table]]` syntax report `unsupportedValue` rather than
being coerced or partially interpreted. Parsers consume memory only and perform
no filesystem access. File convenience functions, if added later, must compose
`xtb.serde` with `xtb.os`.

### Data and API style

- Prefer structs, tagged unions, templates, and function composition; classes
  and runtime reflection are unavailable.
- Keep the name `Array!T` for the allocator-owning growable container. Native
  D slices remain the borrowed representation. `Array!T` is non-copyable and
  its ordinary API is a handwritten member surface colocated with
  `ArrayUnmanaged!T`; D struct-pointer member lookup handles non-null pointer
  receivers without duplicate forwarding overloads. It owns every live element:
  removal, shrinking, clearing,
  release, and destruction run
  element destructors in reverse lifetime order where applicable. Relocation
  uses move construction for elaborate types and leaves moved-from storage
  uninitialized; only POD elements use raw reallocation and byte movement.
  Value append/insert operations accept movable non-copyable structs. Slice
  factories and slice append/insert operations exist only for copyable element
  types. Element construction, movement, and destruction must satisfy the
  container's `nothrow @nogc` contract.
- Use `HashMap!(K, V)` and `HashSet!K` for general allocator-owned hashed
  collections. They use open addressing rather than node allocation and are
  non-copyable. Managed generic-map keys must be copyable and remain immutable
  through the container. `StringViewHashMap!V` is the explicit readability
  alias for `HashMap!(String, V)` and borrows every key's bytes, which must
  outlive the entry. `StringHashMap!V` instead stores
  `OwnedStringUnmanaged` keys, owns one exact allocation per nonempty key, and
  shares one allocator across the whole map. `StringViewHashSet` and
  `StringHashSet` provide the corresponding borrowing and owning set policies.
  All four string hash families accept borrowed `String` lookup/removal values
  without allocation. Lookup returns
  `V*` (or `const(V)*` through a const map) to keep mutation
  explicit. Direct iteration uses
  `foreach (ref const key, ref value; map)`; the `ref` at the call site is the
  explicit mutation marker. `foreach (item; map.pointerItems)` is the
  pointer-oriented alternative and exposes `const(K)* key` plus `V* value`.
  A set similarly offers `ref const` elements or a `pointerItems` range of
  `const(K)*`. Hash and equality policies are compile-time types with
  `nothrow @nogc` pointer-based calls and copyable destructor-free state.
  `HashSeed.init` is deliberately deterministic, while `seeded` permits
  process-specific layouts. The built-in hash remains non-cryptographic under
  either API; applications handling adversarial keys supply a stronger keyed
  custom policy. Insertions and reserve operations keep the old table intact
  when allocation fails. Structural mutation invalidates cursors and storage
  pointers, and iteration order is unspecified.
- Use `FlagSet!E` for a small, allocation-free set of enum flags. Enum values
  are bit positions rather than masks, so sequential enum declarations map to
  consecutive bits and composite enum members are not supported. Positions
  must be non-negative, unique, and no greater than 63. The default storage is
  the smallest fitting unsigned integer; specify `ubyte`, `ushort`, `uint`, or
  `ulong` explicitly wherever size is part of an ABI or persistent format.
  `FlagSet.init` is empty. Mutate individual flags through the UFCS verbs
  `enable`, `disable`, and `toggle`; use `clear` and `fill` for the whole set.
  The corresponding `enabled`, `disabled`, and `toggled` functions return a
  changed value while leaving their input unchanged. `of(flag)` constructs a
  singleton set; there is no second singleton factory.
  `foreach (flag; flags)` yields enabled flags by value in enum declaration
  order. Iteration snapshots the starting mask, so changing the source set in
  the loop body does not change the current traversal.
  Keep the flag enum atomic. Declare named combinations as manifest values of
  the set type, for example
  `enum readWrite = Permissions.of(Permission.read, Permission.write)`, rather
  than adding an overlapping `Permission.readWrite` enum member.
  `enabledCount` reports the population of one set value, `declaredCount`
  reports the number of atomic enum members, and `bitCapacity` reports the
  selected storage width.
  Casts can manufacture undeclared D enum values, so every flag-taking
  operation validates before shifting and panics on an invalid value in checked
  build modes. Release-fast assumes enum values are declared. Use `tryFromBits` for recoverable raw-input validation,
  `fromBits` for trusted masks whose invalidity is a contract violation, and
  `fromBitsTruncated` only when intentionally discarding unknown bits.
- Make state transitions explicit with verbs such as `create`, `reset`,
  `read`, `finish`, and `deinit`.
- Use `create(allocator)` for resource-owning factories and
  `withCapacity(allocator, capacity)` when preallocation is requested. Reserve
  `fromX` for conversion/copy factories and `acquire` for scoped resources.
  Never declare a member named `init`: D reserves `Type.init` for the type's
  default-initialized value, and generic code must remain able to use it.
- Use `scope const` for non-escaping read-only inputs. Use pointers for mutable
  function parameters by default. Owning containers expose receiver-owned
  mutation as member methods (`buffer.append(value)`) rather than free UFCS
  adapters. Genuine free algorithms may use `ref` only when a mutable receiver
  is intrinsic to the algorithm and no owning member surface applies. A
  required pointer is checked/asserted non-null at the boundary; an optional
  pointer documents null behavior. Add `return scope` only when returning a
  borrow tied to an input.
- Avoid boolean parameters when two named functions or an enum communicates
  intent better.
- Validate sizes before multiplication/addition and distinguish byte counts
  from element counts in names and types.
- Keep parsing separate from I/O. Codecs consume byte slices and write through
  explicit sinks/buffers; convenience file functions compose codec and `os`.
- Keep policy out of bindings. Foreign-library constants and calls stay in the
  adapter; resource ownership and validation live in the wrapper above it.

## Capability migration map

The C++ project was reviewed as a capability inventory. Its useful concepts
map to D packages as follows; its exact APIs and implementation defects are not
compatibility requirements.

| C++ area | D destination | Architectural treatment |
| --- | --- | --- |
| allocator, arena, slices, arrays, strings | `xtb.core` | explicit allocator and ownership; no process-global allocator |
| panic, logger, printing, stack traces, thread context | `xtb.core` | explicit sinks/storage/contexts; scratch, current logger, and panic recursion are TLS, while panic observation is process-wide |
| threads, atomics, synchronization | `xtb.threading` | BetterC public primitives over compiler atomics and narrow per-platform thread/parking backends |
| file and directory operations | `xtb.os` | platform-neutral API over per-platform adapters |
| structured serialization | `xtb.serde` | compile-time schemas, explicit ownership, JSON and TOML backends |
| BMP and other media formats | `xtb.codec` | bounds-checked byte transforms with no reflection dependency |
| vectors, matrices, noise | `xtb.math` | value types and pure allocation-free algorithms |
| GLFW window/input | `xtb.window` | opaque handles, callback plus user-context pairs |
| GL loading and shaders | `xtb.graphics.opengl` | generated/foreign binding isolated from safe resource wrappers |
| camera, geometry, material, renderer | `xtb.renderer` | backend-neutral values and orchestration over `graphics` |

Implement in dependency order: `core`, foundational `threading` and `math`,
then `os`, serde/codecs, window/graphics, and finally renderer. A higher layer should not force premature abstractions into a
lower one.

## Change checklist

Before merging an architectural change, verify:

1. Production and tests compile with `-betterC`.
2. Imports still follow the dependency direction and contain no cycle.
3. Ownership, lifetime, failure, and thread-safety are visible in the API.
4. Every `@system` boundary has validation immediately above it.
5. New behavior is tested according to `docs/testing.md`.
6. Public examples still compile without importing internal modules.


## Parser combinators

`xtb.parser` builds reusable parser graphs in a grammar-owned `Arena`. Public
`Parser!T` handles remain small and strongly typed while node implementations
are type-erased, avoiding recursive/template type explosion and improving LSP
lookup. Parser execution is `@nogc` and does not allocate parser machinery;
`.collect()` and semantic actions allocate only when explicitly given a
`ParseContext.outputArena`.

Consumed-input failure commits by default. `attempt()` explicitly permits a
speculative branch to rewind, while `cut()` establishes a semantic commitment
point that survives enclosing attempts. Operator precedence is defined through
structural `expressionTable().level()` groups rather than numeric precedence.
The parser package includes JSON and algebraic arithmetic proving grammars; the
latter asserts AST structure to validate precedence and associativity. See
`design_spec/parser.md` for the complete API and invariants.
