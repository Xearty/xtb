# String API design specification

This specification is implemented by `xtb.core.string` and `xtb.core.utf8`.

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

`StringBuf` owns a growable valid UTF-8 allocation. It remains non-copyable and
exposes mutation through member methods generated from `StringBufUnmanaged`.

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

    size_t byteLength() const pure @safe;
    size_t byteCapacity() const pure @safe;
    bool empty() const pure @safe;
    String view() const return pure @safe;
    Allocator* allocator() return;

    void reserve(size_t byteCapacity);
    bool tryReserve(size_t byteCapacity);

    void append(String value);
    bool tryAppend(String value);
    void append(char ascii);
    bool tryAppend(char ascii);
    void append(dchar codePoint);
    bool tryAppend(dchar codePoint);

    void appendAssumeCapacity(String value);
    void appendAssumeCapacity(char ascii);
    void appendAssumeCapacity(dchar codePoint);

    void insert(size_t byteOffset, String value);
    bool tryInsert(size_t byteOffset, String value);
    void truncateBytes(size_t newByteLength);
    void clear();
    void resetAndRelease();

    bool tryCString(const(char)** output) @system;
    const(char)* cString() return @system;
    const(char)* checkedCString() return @system;
}
```

The `char` overload accepts ASCII only. Non-ASCII scalars use `dchar`; complete
text uses `String`. Insert and truncation offsets must be scalar boundaries.
Appending or inserting a `String` does not rescan it because it is already
inside the text contract.

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
