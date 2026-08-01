# Architecture

## Purpose

`xtbd` is an independent D library collection inspired by the capabilities of
the adjacent C++ project. It is not a line-for-line port and must never import,
generate from, or build files in that project. Design new APIs around D's
strengths while keeping every production target compatible with `-betterC`.

BetterC removes the garbage collector, exceptions, classes, `TypeInfo`,
`ModuleInfo`, associative arrays, built-in threading, and module constructors.
These are architectural constraints, not merely compiler settings. The build
and test paths both compile with `-betterC` so violations are caught early.

## Repository shape

Use conventional D package layout:

```text
xtbd/
├── source/xtb/             # production modules
│   ├── core/               # memory, containers, text, diagnostics
│   ├── math/               # vectors, matrices, scalar algorithms, noise
│   ├── os/                 # libc and platform adapters
│   ├── codec/              # BMP, JSON, and future data formats
│   ├── window/             # window/input abstraction
│   ├── graphics/           # graphics API adapter and resources
│   └── renderer/           # backend-independent rendering policy
├── tests/                  # runners, fixtures, integration/regression tests
├── examples/               # small programs using only public APIs
├── docs/
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

## Dependency direction

Dependencies flow downward:

```text
examples / applications
          |
       renderer
      /        \
 graphics    window
      \        /
       codec / os
           |
          math
           |
          core
           |
       C ABI / libc
```

- `core` depends only on language features and selected `core.stdc` bindings.
- `math` depends on `core` only when it needs shared primitive/result types.
- `os` owns operating-system and libc calls. Higher layers do not call libc
  directly unless they are themselves a foreign-library boundary.
- `codec` is CPU-only parsing/encoding. It does not know about windows, OpenGL,
  or renderer objects.
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
The affine inverse additionally rejects non-affine inputs.

`Random` implements a stable PCG32 sequence. Callers always supply a seed and
may supply an independent stream; there is no process-global random state.
`unit()` returns values in `[0, 1)`, and `below(bound)` uses rejection sampling
instead of modulo-biased range reduction.

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
failure; complete I/O loops over short transfers and interruptions. Whole-file
helpers use caller-owned `Array!ubyte`, preserving embedded NUL bytes and
making allocation explicit.

Directory enumeration is streaming. `DirectoryEntry.name` borrows libc's entry
buffer and expires when the iterator advances or closes. There is deliberately
no linked-list result. `walkDirectory` performs depth-first traversal through a
non-allocating callback receiving a temporary full `Path`; that path must not
escape the callback. Traversal receives an explicit temporary allocator so
arbitrary directory depth does not consume nested scratch arenas. Callers
needing persistence copy entries into their chosen container and allocator.

`environmentVariable` returns a process-owned borrowed view that later
environment mutation can invalidate. `currentDirectory`, `executablePath`, and
`canonicalPath` write owned bytes into a supplied `StringBuf`. Read-only maps
remain valid until their `MappedFile` is destroyed. Monotonic timestamps serve
elapsed-time measurement; wall-clock timestamps are Unix-epoch nanoseconds and
may jump when the system clock changes.

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

### Diagnostics and fatal crashes

Stack traces use caller-provided frame and text storage. Symbol capture,
demangling, signature tokenization, styling, and rendering must not allocate.
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
same behavior with `SignatureFormat`, including their initial column and base
indentation. A zero column limit is treated as unbounded.

```text
Renderer.submit(
    ref Context,
    scope const(Command)[],
    CompletionHook
) -> RenderResult nothrow @nogc
```

`StackTraceStyle` owns no text or allocation. Its `StackTraceColors` store
enabled 8-bit ANSI indices, normally from a preset or `fromAnsi8`; escape
sequences are emitted directly into the destination writer. Rendering uses a
plain theme when ANSI control sequences are inappropriate. Signature coloring
is lexical presentation only; failure to classify a token never changes or
discards the token's source bytes.

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
qualified name. Set `moduleDisplay = ModuleDisplay.full` when disambiguation or
copying the exact qualified signature is more important than compact output.

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
Calling the allocator dereferences the slot and passes the handle itself back
as the callback's opaque first argument. It is not a two-word
`{ function, context }` pair.

Conceptually, the operation is:

```d
alias Allocator = void* function(
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
stateful allocator embeds that slot as the first field of its state struct; for
example, an arena handle is `&arena.allocator`, and its callback casts the
opaque argument back to `Arena*`. This intrusive convention keeps the public
handle to one pointer, but it depends on an explicit layout invariant. Enforce
that invariant with `static assert(Arena.allocator.offsetof == 0)` for every
stateful allocator implementation, keep the callback signature identical, and
never move or copy the state while its allocator handle is in use.

An operation that retains or returns owned memory receives `Allocator*`
explicitly or uses an owning object that already stores that handle. Document
how long the allocator slot and its containing state must remain alive. Do not
introduce a mutable global "current allocator."

Typed allocation returns raw storage; it does not construct elements. Typed
reallocation is restricted to POD representations, and
`allocateZeroed!T` is available only when `T` is POD. Zeroed allocation means
every byte is zero, not `T.init`: types with destructors, postblits, assignment
hooks, or other lifetime semantics must be constructed explicitly in raw
storage and destroyed before deallocation.

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

The string model has two deliberately separate types: `String` is a
read-only borrowed view, and `StringBuf` is an owning mutable buffer and
builder. Do not collapse them into one type and do not use a mutable D slice as
the public string abstraction.

#### `String`: read-only borrowed text

Use D's native slice representation rather than recreating pointer and length
accessors in a wrapper struct:

```d
alias String = const(char)[];
```

`String` does not own, allocate, reallocate, free, or mutate its storage.
Constness prevents user code from modifying bytes through the view. Copying it
copies only its pointer and length; its bytes must outlive every copied or
derived view. It is a simple, trivially copyable value with no destructor or
hidden state. A substring, trim, prefix, suffix, split token, or other operation
that can reuse existing bytes returns another `String` without allocation.
Use project free functions for equality, comparison, searching, hashing, and
transformation, invoked through UFCS (`text.trim()`, `text.find(needle)`). Do
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

Strings are byte-addressed. Text-producing APIs emit UTF-8, but the core view
does not silently validate, normalize, count code points, or reinterpret bytes.
APIs requiring valid UTF-8 validate explicitly and report an error. File paths
and other platform byte strings may use `String` without pretending that
every sequence is Unicode. Unicode-aware iteration and transformation belong
in explicitly named utilities.

#### `StringBuf`: owned mutable storage

`StringBuf` owns a growable byte allocation and stores its `Allocator*`, data
pointer, logical length, and capacity. It is non-copyable, has a useful empty
zero state, and releases its allocation in `deinit`/RAII cleanup according to
the allocator contract. Ownership transfer, if needed, uses an explicitly
named move/release operation that leaves the source empty; ordinary assignment
must not duplicate ownership.

All mutation occurs through `StringBuf`, never through `String`. Free functions
that modify a buffer use `ref StringBuf` as their first parameter so they work
naturally with UFCS. This is the narrow exception to the project's pointer-for-
mutation rule. Other mutable parameters remain pointers. Function names are
short verbs; never prefix every operation with the type name.

```d
StringBuf buffer = StringBuf.create(allocator);
buffer.append(prefix);
buffer.appendByte(':');
buffer.append(value);
String result = buffer.view();
```

Here `buffer.append(value)` is UFCS for `append(buffer, value)`, whose first
parameter is `ref StringBuf buffer`. Mutating verbs make the state change clear
without repeating the type name or requiring `&` at every call. Apply the same
rule to `Array!T` and other owning containers. Reserve, resize, append, prepend,
insert, replace-in-place, clear, and formatting operations validate overflow
before changing the buffer. On a recoverable allocation failure the original
contents remain valid unless the operation documents otherwise.

`view()` returns a read-only `String` borrowing the current contents. Any
operation that can reallocate, shift, overwrite, clear, release, or destroy the
buffer invalidates affected views. The type system must not offer an implicit
conversion that hides this borrowing relationship. To preserve text after the
buffer changes or dies, initialize a different `StringBuf` from the view
using the destination allocator.

Copying a `String` into owned storage is explicit:

```d
StringBuf owned = StringBuf.fromString(allocator, input);
```

Builder-style utilities use `ref StringBuf output` as their first UFCS receiver
when composition or allocation reuse matters. Convenience functions may return
`StringBuf` by move. Utilities returning an allocator-backed `String` document
that the allocator, not the view, owns its bytes and when those bytes become
invalid.

#### C strings and termination

`String` is not NUL-terminated by contract and must never be passed
directly to a C API expecting `const char*`. A C-boundary helper copies into a
`StringBuf`--normally scratch-backed--and appends one terminator outside the
logical length. `StringBuf` may maintain spare terminator storage, but the
NUL is not part of `view()`, equality, hashing, or iteration. Embedded NUL must
be rejected when the target C API would truncate it.

A pointer returned for C interop is valid only until the buffer is mutated or
its owner/scratch scope ends. It must not escape unless the foreign API
explicitly copies the string. Never cast away constness to avoid this
conversion.

#### API rules

- Accept `String` by value for read-only string input.
- Accept `ref StringBuf` as the first parameter of a mutating UFCS operation;
  use pointers for any additional mutable parameters.
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
runtime precondition and immediately calls the project's panic handler. There
is no status result, nullable scratch value, or recovery branch in callers.

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

    StringBuf temporary = StringBuf.create(scratch.allocator());
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

### Data and API style

- Prefer structs, tagged unions, templates, and function composition; classes
  and runtime reflection are unavailable.
- Keep the name `Array!T` for the allocator-owning growable container. Native
  D slices remain the borrowed representation. `Array!T` is non-copyable and
  its mutating free functions use a `ref Array!T` UFCS receiver. It owns every
  live element: removal, shrinking, clearing, release, and destruction run
  element destructors in reverse lifetime order where applicable. Relocation
  uses move construction for elaborate types and leaves moved-from storage
  uninitialized; only POD elements use raw reallocation and byte movement.
  Value append/insert operations accept movable non-copyable structs. Slice
  factories and slice append/insert operations exist only for copyable element
  types. Element construction, movement, and destruction must satisfy the
  container's `nothrow @nogc` contract.
- Make state transitions explicit with verbs such as `create`, `reset`,
  `read`, `finish`, and `deinit`.
- Use `create(allocator)` for resource-owning factories and
  `withCapacity(allocator, capacity)` when preallocation is requested. Reserve
  `fromX` for conversion/copy factories and `acquire` for scoped resources.
  Never declare a member named `init`: D reserves `Type.init` for the type's
  default-initialized value, and generic code must remain able to use it.
- Use `scope const` for non-escaping read-only inputs. Use pointers for mutable
  parameters by default. The first receiver of a mutating UFCS operation may
  use `ref`, allowing `buffer.append(value)` for `StringBuf`, `Array!T`, and
  similar stateful values without permitting `ref` throughout arbitrary APIs.
  A required pointer is checked/asserted non-null at the boundary; an optional
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
| panic, logger, printing, stack traces, thread context | `xtb.core` | explicit sinks/storage/contexts; scratch context and panic recursion are TLS, while panic observation is process-wide |
| file and directory operations | `xtb.os` | platform-neutral API over per-platform adapters |
| BMP and JSON | `xtb.codec.bmp`, `xtb.codec.json` | bounds-checked byte parsers, explicit errors, I/O-independent core |
| vectors, matrices, noise | `xtb.math` | value types and pure allocation-free algorithms |
| GLFW window/input | `xtb.window` | opaque handles, callback plus user-context pairs |
| GL loading and shaders | `xtb.graphics.opengl` | generated/foreign binding isolated from safe resource wrappers |
| camera, geometry, material, renderer | `xtb.renderer` | backend-neutral values and orchestration over `graphics` |

Implement in dependency order: `core`, `math`, `os`, codecs, window/graphics,
then renderer. A higher layer should not force premature abstractions into a
lower one.

## Change checklist

Before merging an architectural change, verify:

1. Production and tests compile with `-betterC`.
2. Imports still follow the dependency direction and contain no cycle.
3. Ownership, lifetime, failure, and thread-safety are visible in the API.
4. Every `@system` boundary has validation immediately above it.
5. New behavior is tested according to `docs/testing.md`.
6. Public examples still compile without importing internal modules.
