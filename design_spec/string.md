# String API design specification

This specification is implemented by `xtb.core.string`,
`xtb.core.owned_string`, and `xtb.core.utf8`.

## Representation and invariant

```d
alias String = const(char)[];
```

`String` is a borrowed read-only UTF-8 view. It remains an alias so literals
work directly, copying remains a pointer-and-length copy, UFCS remains natural,
and no wrapper overloads are required merely to call `consume("text")`.

The alias cannot enforce valid UTF-8. The library therefore uses the same
boundary model as Rust's `str`, adapted to D:

- external bytes are validated before becoming ordinary text;
- library text producers preserve valid UTF-8;
- unchecked conversion is visibly named and `@system`;
- `String.length`, indexing, and built-in slicing are byte/code-unit operations;
- library slicing checks UTF-8 boundaries; and
- Unicode scalar operations are explicit and never called character indexing.

`char` is one UTF-8 code unit, `u8` is an encoding-neutral byte, and `dchar` is
used for one Unicode scalar value. Grapheme clusters are outside this API.

## Byte-oriented API

The foundational `xtb.core.string` surface is:

```d
size_t byteLength(String value) pure @safe;
const(u8)[] bytes(return scope String value) pure @trusted;

bool empty(String value) pure @safe;
char frontCodeUnit(String value) @safe;
char backCodeUnit(String value) @safe;

String sliceBytes(
    return scope String value,
    size_t beginByteOffset,
    size_t endByteOffset,
) @safe;

String prefixBytes(
    return scope String value,
    size_t endByteOffset,
) @safe;

String suffixBytes(
    return scope String value,
    size_t beginByteOffset,
) @safe;

size_t find(String value, String needle) pure @safe;
size_t findLast(String value, String needle) pure @safe;
size_t findCodeUnit(String value, char codeUnit) pure @safe;
size_t findLastCodeUnit(String value, char codeUnit) pure @safe;
size_t findCodePoint(String value, dchar codePoint) @safe;
size_t findLastCodePoint(String value, dchar codePoint) @safe;

bool contains(String value, String needle) pure @safe;
bool containsCodeUnit(String value, char codeUnit) pure @safe;
bool containsCodePoint(String value, dchar codePoint) @safe;
bool startsWith(String value, String prefix) pure @safe;
bool endsWith(String value, String suffix) pure @safe;

String trimAsciiStart(return scope String value) pure @safe;
String trimAsciiEnd(return scope String value) pure @safe;
String trimAscii(return scope String value) pure @safe;
```

`String.length` and `byteLength` return bytes. `byteLength` is useful where the
unit must be obvious in surrounding code; it does not hide or deprecate D's
slice property. `bytes` is a zero-copy read-only reinterpretation.

`find(String)` and `findLast(String)` follow Rust's familiar naming and return
byte offsets. A match between valid UTF-8 strings starts and ends at scalar
boundaries. Searches for one raw `char` say `CodeUnit`; searches for a scalar
accept `dchar`, encode it, and also return a byte offset.

`sliceBytes`, `prefixBytes`, and `suffixBytes` require in-range scalar
boundaries and panic on contract violation. They never round. Callers enforcing
a byte budget explicitly use `floorCodePointBoundary` or
`ceilCodePointBoundary` first.

The ambiguous `front`, `back`, `slice`, `head`, `tail`, `truncateLeft`,
`truncateRight`, `find(char)`, `findLast(char)`, `contains(char)`, `trimLeft`,
`trimRight`, and `trim` APIs are removed. Built-in slicing remains available but
is an unchecked operation: a split sequence must not be passed as ordinary
`String`.

## Checked conversion

```d
Utf8StringResult asString(return scope const(u8)[] bytes) @trusted;
String asStringUnchecked(return scope const(u8)[] bytes) pure @system;

Utf8StringResult fromCString(const(char)* value) @system;
String fromCStringUnchecked(const(char)* value) @system;
```

`asString` validates once, allocates nothing, and returns a view borrowing the
source. On failure its value is empty and its error identifies the exact byte.
A mutable source alias must not change while the validated view is used.

`fromCString` requires a non-null pointer, finds the terminating NUL, validates
the preceding bytes, and returns the same result type. Embedded NUL cannot be
represented by this boundary. The unchecked forms mean the caller already has
an encoding proof; malformed input violates the `String` contract.

Process output, file contents, network packets, and general binary storage stay
`u8[]` until checked conversion. Arbitrary binary ownership uses `Array!u8`.

## Allocating immutable transformations

`String` remains a borrowed view even when a transformation creates different
bytes. The allocation context selects which object owns those new bytes:

- `Allocator*` returns `OwnedString`, so the result itself carries the explicit
  cleanup obligation; and
- `Arena*` returns `String`, because the arena owns the backing storage and
  individual string cleanup would be redundant.

The two families deliberately use the same UFCS-friendly operation names:

```d
bool tryCopy(String value, Allocator* allocator, OwnedString* output);
OwnedString copy(String value, Allocator* allocator);
bool tryCopy(String value, Arena* arena, String* output);
String copy(String value, Arena* arena);

bool tryConcat(String left, String right, Allocator* allocator, OwnedString* output);
OwnedString concat(String left, String right, Allocator* allocator);
bool tryConcat(String left, String right, Arena* arena, String* output);
String concat(String left, String right, Arena* arena);

bool tryReplace(
    String value,
    String from,
    String to,
    Allocator* allocator,
    OwnedString* output,
);
OwnedString replace(String value, String from, String to, Allocator* allocator);
bool tryReplace(
    String value,
    String from,
    String to,
    Arena* arena,
    String* output,
);
String replace(String value, String from, String to, Arena* arena);

bool tryJoin(
    scope const(String)[] values,
    String separator,
    Allocator* allocator,
    OwnedString* output,
);
OwnedString join(
    scope const(String)[] values,
    String separator,
    Allocator* allocator,
);
bool tryJoin(
    scope const(String)[] values,
    String separator,
    Arena* arena,
    String* output,
);
String join(scope const(String)[] values, String separator, Arena* arena);

bool tryEscape(String value, Allocator* allocator, OwnedString* output);
OwnedString escape(String value, Allocator* allocator);
bool tryEscape(String value, Arena* arena, String* output);
String escape(String value, Arena* arena);
```

For the `Allocator*` family, successful nonempty results use exact-sized
immutable storage with no trailing C terminator. Empty results remain valid
`OwnedString` values bound to the supplied allocator without allocating. A
fallible function requires an empty `OwnedString` output and leaves it empty on
failure. End a successful result with `deinit()`.

For the `Arena*` family, each successful nonempty operation requests exactly the
logical output byte length from the arena and returns only the resulting
pointer-and-length `String` view. Empty results allocate nothing. Fallible
operations leave the caller's `String` output unchanged on failure. The returned
view is valid only until its arena storage is rewound, cleared, or deinitialized;
when called inside a `TempArena`/`ScratchScope`, that includes the corresponding
pop/scope exit. Never call `deinit()` on the returned `String`.

Typical arena code therefore stays lightweight:

```d
String normalized = rawPath.replace("//", "/", scratch.arena);
String[2] parts = [method, normalized];
String key = parts[].join(" ", scratch.arena);
```

Promotion to an independent lifetime is explicit:

```d
OwnedString persistent = key.copy(mallocAllocator());
// ... use persistent after the scratch scope ...
persistent.deinit();
```

Passing `arena.allocator` still selects the `Allocator*` overload and therefore
produces `OwnedString`; prefer passing `Arena*` directly when region lifetime is
the intended ownership model. `OwnedStringUnmanaged` remains for contextual
individual ownership, not ordinary arena-backed immutable strings.

Use `StringBuf` instead when the new text will be mutated, incrementally built,
or converted to a NUL-terminated C string. Repeated `StringBuf` growth on an
arena can abandon intermediate buffers until rewind, so mutable arena builders
are a separate policy problem rather than an implicit part of this API.

### Direct `OwnedString` transformations

`OwnedString` exposes the immutable transformation family directly so routine
owned-string code does not need to spell `.view` merely to transform bytes.
When no allocation context is supplied, the result uses the source owner's
stored allocator:

```d
OwnedString source = "hello".copy(heap);
scope (exit) source.deinit();

OwnedString concatenated = source.concat(" world");
scope (exit) concatenated.deinit();

OwnedString replaced = concatenated.replace("world", "XTB");
scope (exit) replaced.deinit();

OwnedString escaped = replaced.escape();
scope (exit) escaped.deinit();
```

The explicit-context overloads remain available:

```d
OwnedString otherHeap = source.concat("!", otherAllocator);
scope (exit) otherHeap.deinit();

String temporary = source.concat("!", &arena);
```

The complete ownership matrix is therefore:

```text
String + Allocator*       -> OwnedString
String + Arena*           -> String
OwnedString + default     -> OwnedString using the source allocator
OwnedString + Allocator*  -> OwnedString using the explicit allocator
OwnedString + Arena*      -> String owned by the arena
```

`OwnedString.clone()` creates another independent owner with the source
allocator; `clone(Allocator*)` selects a different independent allocator.
`OwnedString.copy(Arena*)` copies into arena-owned storage. `copy(Allocator*)`
is intentionally not duplicated on `OwnedString`: `clone` is the ownership
spelling for creating another independent owner.

The direct `tryConcat`, `tryReplace`, and `tryEscape` overloads follow the same
context-selection rules and preserve the existing empty-output failure
contract. Direct methods are callable through `const OwnedString`; allocating
through the stored allocator does not mutate the source string.

## Scalar traversal

The scalar API is defined by [`utf8.md`](utf8.md):

```d
size_t codePointCount(String value);
CodePointRange codePoints(return scope String value);
CodePointOffsetRange codePointsWithOffsets(return scope String value);
```

`CodePointRange` yields `dchar`. `CodePointOffsetRange` yields
`DecodedCodePoint`, containing the scalar, its byte offset relative to the
original string, and its encoded byte length. Both ranges are copyable,
allocation-free, bidirectional ranges.

There is no scalar subscript. Locating the Nth scalar is O(bytes) and callers
must expose that cost through traversal. Neither range performs grapheme
segmentation or normalization.

## `StringBuf`

`StringBuf` owns a growable valid UTF-8 allocation. It remains non-copyable.
Its struct contains ownership state, static factories, D-required hooks, and
its ordinary handwritten member API. The declarations are colocated in
`xtb.core.string`, so language servers can navigate directly to the operation
selected for a `StringBuf` receiver.

```d
struct StringBuf
{
    static StringBuf create(Allocator* allocator);
    static StringBuf withCapacity(Allocator* allocator, size_t byteCapacity);
    static StringBuf fromString(Allocator* allocator, String value);
    static bool tryFromString(
        Allocator* allocator,
        String value,
        StringBuf* output,
    );

    size_t byteLength() const;
    String view() const return;
    bool tryAppend(String value);
    void append(String value);
    void append(dchar codePoint);
    bool tryAssign(String value);
    void trimAsciiInPlace();
    bool tryReplaceInPlace(String from, String to);
    void replaceInPlace(String from, String to);
    bool tryAppendEscaped(String value);
    void appendEscaped(String value);
    bool tryEscapeInPlace();
    void escapeInPlace();
    bool removePrefix(String prefix);
    Array!String split(String separator, Allocator* allocator) const;
    bool tryCString(const(char)** output) @system;
    const(char)* checkedCString() return @system;
}
```


D automatically permits member lookup through a non-null `StringBuf*`, so no
parallel pointer-forwarding overload set is needed. Checked builds use the
managed-container invariant for null-receiver diagnostics. No adapter
declarations are generated with mixins or reflection; see
[`docs/managed-containers.md`](../docs/managed-containers.md).

The `char` overload accepts ASCII only. Non-ASCII scalars use `dchar`; complete
text uses `String`. Insert and truncation offsets must be scalar boundaries.
Appending or inserting a `String` does not rescan it because it is already
inside the text contract.

`replaceInPlace` and `escapeInPlace` make mutation explicit in the operation
name. `tryReplaceInPlace` and `tryEscapeInPlace` reserve every required byte
before changing logical contents, so allocation failure leaves the buffer
unchanged. Replacement arguments that alias the current buffer are supported:
aliased `from`/`to` views are snapshotted before reserve/reallocation so growth
cannot invalidate them. The compatibility spelling `tryReplace` remains but new
code should prefer `tryReplaceInPlace`.

`escapeInPlace` escapes the buffer's current contents. It is different from
`appendEscaped(value)`, which appends an escaped representation of another
string; `tryAppendEscaped(value)` is that operation's fallible form. There is no
`tryEscape(value)` alias because it would be ambiguous next to
`tryEscapeInPlace()`. Concatenation remains `append`; there is no redundant
`concatInPlace` operation.

`appendByte` is removed. Package-private printer/serde code may append raw
chunks only while maintaining a documented transaction invariant: no invalid
intermediate `String` may escape, and successful completion must produce valid
UTF-8.

`StringBuf.fromBytesUnchecked` and its fallible counterpart remain `@system`
for audited, already validated bytes. They are not binary constructors.

`StringBuf` does not maintain a terminator after every mutation. `tryCString`
reserves one extra byte when necessary, writes a trailing NUL outside
`byteLength`, and leaves the logical contents unchanged. `cString` is its
panicking counterpart. `checkedCString` additionally rejects embedded NUL
bytes. Every returned pointer is invalidated by the next mutation or by
buffer destruction.

## Equality, ordering, and hashing

Equality, `compare`, and hashing operate on exact UTF-8 bytes without
normalization. Built-in `String` equality remains symmetric with literals.
`StringBuf` equality remains symmetric with `String` and other buffers. Hashing
uses the same bytes as equality.

Lexicographic byte order for valid UTF-8 agrees with scalar-value order, but it
is not locale collation and normalization-equivalent strings may compare
unequal.

## Implementation requirements

- Keep `String` declared only in `xtb.core.types` and publicly re-export it.
- Preserve literal calls such as `consume("text")`.
- Validate every foreign byte-to-text boundary or name it unchecked.
- Use `byteOffset`, `byteLength`, and `byteCapacity` in text APIs and locals.
- Preserve UTF-8 across every public `StringBuf` mutation.
- Replace duplicated validators and encoders with `xtb.core.utf8`.
- Keep all operations BetterC-compatible, allocation-free unless an explicit
  allocator or owning buffer is involved, and fully covered by sanitizer tests.
