# Standard-library roadmap

This document ranks the important general-purpose facilities that are still
missing from xtb. It is a forward-looking roadmap, not a compatibility list for
the C++ project. The current implementation ledger remains in
[`core-gap-analysis.md`](core-gap-analysis.md).

The ranking considers correctness dependencies, how many later libraries a
feature enables, and how often applications need it. A lower number should
normally be implemented first. Adjacent entries may be delivered together when
they share infrastructure.

All additions must remain BetterC-compatible. They must preserve the project's
explicit allocation model, avoid exceptions and hidden process-global state,
and leave unsupported operating systems buildable through explicit versioned
implementations.

## P0: foundational gaps

### 1. UTF-8 validation and traversal

`String` and `StringBuf` are intended to contain valid UTF-8, but that contract
cannot yet be established at all input boundaries. This is the most important
correctness gap in the text layer.

The prescriptive text wrapper, UTF-8 API, and migration plan are specified in
[`../design_spec/string.md`](../design_spec/string.md) and
[`../design_spec/utf8.md`](../design_spec/utf8.md).

Implement a small UTF-8 module with:

- validation that reports the byte offset and reason for invalid input;
- checked construction and assignment at external byte boundaries;
- forward and reverse code-point decoding;
- code-point encoding and exact encoded-size calculation;
- allocation-free code-point iteration over `String`;
- an explicit unchecked path for trusted data.

JSON and TOML parsing, process text conversion, file input, and future networking
code should use this common implementation. Do not add normalization, locale,
case folding, or grapheme segmentation to this milestone.

### 2. Generic algorithms and ordering

The containers expose usable storage and iteration, but callers should not have
to reimplement common algorithms. Add slice-first, allocation-free algorithms:

- `find`, `findIf`, `contains`, `count`, `any`, `all`, and equality;
- `minElement`, `maxElement`, and lexicographical comparison;
- `lowerBound`, `upperBound`, `equalRange`, and binary search;
- reverse, rotate, partition, remove, and adjacent duplicate removal;
- heap operations and an in-place general-purpose sort;
- a stable sort only when supplied with explicit temporary storage or an
  allocator.

Comparators and predicates should work with D templates and UFCS. Default
ordering must be unsurprising, and algorithms must document whether they
invalidate references or reorder equal values.

### 3. Binary readers, writers, and endian utilities

Build an allocation-free binary-data foundation before adding another wire or
file format. It should contain:

- bounded `ByteReader` and `ByteWriter` cursors;
- checked fixed-width integer and floating-point reads and writes;
- little-endian and big-endian operations;
- byte swapping and alignment-safe loads and stores;
- varint and zig-zag integer encoding;
- exact encoded-size functions and useful error offsets;
- explicit operations for raw byte spans versus UTF-8 strings.

This layer should not know about serde schemas. Binary serde backends, network
protocols, checksums, and file-format parsers can build on it later.

### 4. Seekable and buffered I/O

The project can read and write files and pipes, but it lacks the reusable I/O
layer needed by parsers and protocols. Add:

- file seek, tell, length, and truncate operations;
- `readExact`, `writeAll`, and explicit end-of-input handling;
- buffered readers and writers using caller-owned or explicitly allocated
  storage;
- line and delimiter reading without silently allocating;
- explicit flush and close-error reporting;
- lightweight reader/writer adapters for files, pipes, memory, and callbacks.

Prefer value types and static dispatch. Do not create a virtual stream class
hierarchy, a global standard stream registry, or implicit buffering.

## P1: broadly useful system facilities

### 5. Process convenience layer

The low-level child process, `communicate`, and borrowed pipeline facilities are
implemented. Complete the already designed high-level layer:

- `RunOptions`, `RunOutput`, and `run`;
- `PipelineRunOptions` and `runPipeline`;
- capture limits, timeouts, and clear ownership of captured buffers;
- consistent propagation of spawn, I/O, timeout, and exit-status failures.

It must remain a wrapper over the low-level API. Commands are argument arrays;
never invoke a shell implicitly. Fluent option construction should improve
call-site readability without concealing allocation or ownership.

### 6. Operating-system entropy

Add a small API for filling a byte slice from the operating system's secure
random source. Keep it separate from deterministic `xtb.math.random`, make
partial reads and interruption handling internal, and return a concrete OS
error. This is required before UUIDs, tokens, secure temporary names, or network
protocol code can be implemented responsibly.

### 7. Filesystem completion

The existing layer already covers common file access, metadata, directory
iteration, recursive walking, canonical paths, and copying. Add the operations
needed for robust application workflows:

- recursive directory creation and removal;
- temporary files and directories with RAII cleanup helpers;
- symlink creation and inspection, plus hard links where supported;
- permissions and timestamp access;
- atomic replacement and an atomic-write helper;
- richer path components, extension manipulation, lexical normalization, and
  relative-path calculation.

Path operations must distinguish lexical transformation from filesystem access.
Destructive recursive operations must be explicit and must not follow directory
symlinks by default.

### 8. Threads and synchronization

Provide a thin, owned system-thread layer with join/detach state, followed by
mutexes, condition variables, reader/writer locks, semaphores, and once-only
initialization. Integrate `ThreadContext` explicitly for threads that request
scratch storage; do not silently construct one for every thread.

Synchronization objects should be non-copyable owners, expose native failures
where failures are meaningful, and state their memory-order guarantees. Use D's
BetterC-compatible atomic primitives directly or wrap them only when the wrapper
adds a project-wide invariant.

### 9. Readiness polling

Introduce an event-readiness abstraction before attempting an asynchronous
runtime. Start with a portable poll-style API, deadline support, stable user
tokens, and a wake-up mechanism. Optimized epoll or kqueue backends can follow
without changing the public model.

The same poller should serve pipes, processes, and sockets. Do not add coroutines,
an executor, or hidden worker threads at this stage.

### 10. Networking

After binary cursors, I/O adapters, and polling exist, implement:

- an owned socket handle and socket-pair support;
- IPv4 and IPv6 address parsing and formatting;
- TCP bind, listen, accept, connect, shutdown, and common options;
- UDP send and receive;
- blocking and non-blocking modes;
- DNS resolution with explicit allocation and ownership.

TLS and HTTP should remain separate libraries backed by established external
implementations. The socket API must not imply that one `send` or `receive` call
transfers an entire message.

### 11. Civil time and timestamp formatting

Extend `Duration` and the existing OS clocks with distinct monotonic instants and
wall-clock timestamps. Add checked calendar conversion, UTC offsets, and strict
ISO-8601/RFC-3339 parsing and formatting.

Do not bundle a timezone database or locale system. Those are large, independently
versioned data concerns and should be optional later packages.

## P2: high-leverage additions

### 12. Additional allocator strategies

Add a fixed-buffer allocator, a fallback allocator, and a pool/slab allocator
for fixed-size objects. Consider a virtual-memory reserve/commit allocator in the
OS package once a real consumer exists.

Each allocator must have precise alignment, ownership, reset, and deallocation
rules. Avoid a global default allocator, allocator registries, and wrappers whose
only purpose is renaming the existing allocator callback.

### 13. A project-owned tagged sum type

Evaluate and, if it proves simpler than relying on a runtime-heavy dependency,
implement a BetterC `SumType` with:

- an explicit active tag;
- correct construction, destruction, copying, and moving for non-POD members;
- exhaustive visitation and checked typed access;
- no hidden allocation.

This would give serde a natural destination for explicitly tagged unions. Do not
support untagged serde unions, and do not couple the initial type to serde.

### 14. Remaining core containers

Add only containers with distinct storage or performance semantics:

- a deque or circular buffer;
- a priority queue built on the heap algorithms;
- fixed and dynamic bit sets;
- optionally, a small-vector type after measuring a concrete use case.

Do not grow a container catalogue merely to mirror another standard library.
Existing slices, `Array`, hash containers, and intrusive containers already cover
most general-purpose storage.

### 15. Command-line parsing

Build an allocation-conscious parser over borrowed `argv` values. It should
support short and long options, repeatable options, positional arguments,
subcommands, generated usage text, and clear diagnostics. Parsed strings should
remain borrowed unless the caller explicitly requests ownership.

Shell command construction and shell escaping are separate concerns and must not
be folded into this API.

### 16. Text and binary encodings

Implement streaming hex and Base64 encoders/decoders with exact size queries,
caller-provided output, and precise invalid-input offsets. Add CRC32 or other
checksums only alongside a concrete protocol or file-format consumer; do not
present a checksum as cryptographic integrity.

### 17. Dynamic library loading

Provide an RAII dynamic-library handle, typed symbol lookup helpers, and concrete
loader errors. Keep platform naming and search-path policy explicit. This should
be implemented only for supported platforms while other platforms continue to
compile with a clear unsupported result.

### 18. Reusable test and benchmark support

Promote generally useful pieces of the internal test infrastructure into a small
BetterC testing package:

- value and slice comparison diagnostics;
- crash/death-test execution;
- temporary-directory fixtures;
- deterministic clocks, entropy providers, and I/O test doubles;
- a minimal benchmark runner with warm-up and monotonic timing.

Tests should remain next to the source they exercise. This package must not make
production modules depend on a test runtime.

## P3: defer until demanded by a real consumer

The following are plausible libraries, but their implementation and maintenance
cost is too high to justify ahead of a concrete use case:

1. Unicode normalization, case folding, grapheme segmentation, and data tables.
2. Regular expressions and a general pattern-matching engine.
3. Compression and archive formats.
4. TLS, HTTP, and higher-level network protocols.
5. An asynchronous executor or coroutine runtime.
6. Shared-memory IPC and cross-process synchronization.
7. Arbitrary-precision integers, decimal arithmetic, and localization.
8. A timezone database and locale-sensitive formatting.
9. A plugin framework built on dynamic loading.
10. UUIDs and other identifier formats, after secure entropy exists.

## Deliberate non-goals

These are not omissions that should be filled by default:

- A universal `Result!T`. Concrete error values plus output parameters remain a
  good fit for BetterC and explicit ownership. Reconsider this only if repeated
  composition problems appear in real APIs.
- A clone of Phobos ranges. Slices, small cursor types, UFCS, and focused
  algorithms provide the useful parts without importing a second abstraction
  system.
- GC-owned strings or containers, exceptions, runtime reflection, and class-based
  stream hierarchies.
- Global allocators, loggers, scratch pools, thread contexts, or other mutable
  singleton services.
- Windows implementations before they are requested. Platform-neutral modules
  must still compile and report unsupported operations clearly.

## Recommended next milestone

Implement ranks 1 through 3 as one cohesive milestone: validated UTF-8, generic
algorithms, and binary cursors. They are locally testable, have no platform
dependency, and establish the contracts required by nearly every later text,
serialization, filesystem, and networking feature.
