# String API design specification

## Decision

`String` becomes a distinct, trivially copyable borrowed UTF-8 view. It is no
longer an alias of `const(char)[]`.

The new type exists to enforce properties that an alias cannot:

- ordinary construction establishes valid UTF-8;
- integer indexing and built-in slicing are unavailable;
- byte offsets and Unicode scalar traversal have separate APIs;
- returning a substring can check UTF-8 boundaries;
- raw storage conversion is explicit; and
- read-only string operations can be real member functions.

`String` remains a two-word value containing one D slice. It owns no memory,
has no destructor, allocates nothing, and copies by value. `String.init` is a
valid empty string.

## Representation

```d
module xtb.core.string;

nothrow @nogc:

struct String
{
private:
    const(char)[] codeUnits_;

public:
    // Validates and panics if utf8 is malformed. Intended for literals and
    // other programmer-controlled text, not untrusted external input.
    this(return scope const(char)[] utf8) @safe;

    size_t byteLength() const pure @safe;
    bool empty() const pure @safe;

    const(char)[] codeUnits() const return scope pure @safe;
    const(u8)[] bytes() const return scope pure @trusted;

    char codeUnitAt(size_t byteOffset) const @safe;

    String sliceBytes(
        size_t beginByteOffset,
        size_t endByteOffset,
    ) const return scope @safe;

    String prefixBytes(size_t endByteOffset) const return scope @safe;
    String suffixBytes(size_t beginByteOffset) const return scope @safe;

    bool isCodePointBoundary(size_t byteOffset) const @safe;
    size_t floorCodePointBoundary(size_t byteOffset) const @safe;
    size_t ceilCodePointBoundary(size_t byteOffset) const @safe;

    size_t codePointCount() const @safe;
    CodePointRange codePoints() const return scope pure @safe;
    CodePointOffsetRange codePointsWithOffsets() const return scope pure @safe;

    size_t find(String needle) const pure @safe;
    size_t findLast(String needle) const pure @safe;
    size_t findCodeUnit(char codeUnit) const pure @safe;
    size_t findCodePoint(dchar codePoint) const @safe;

    bool contains(String needle) const pure @safe;
    bool containsCodePoint(dchar codePoint) const @safe;
    bool startsWith(String prefix) const pure @safe;
    bool endsWith(String suffix) const pure @safe;

    int compare(String other) const pure @safe;
    bool opEquals(String other) const pure @safe;
    bool opEquals(scope const(char)[] codeUnits) const pure @safe;
    size_t toHash() const pure @safe;
}
```

The exact implementation may place larger algorithms outside the struct and
forward to package-private primitives, but this is the public surface. Read-only
operations are members. Mutating `StringBuf` operations remain free functions
whose first UFCS receiver is `ref StringBuf`.

There is deliberately no:

- `alias this` to the underlying slice;
- implicit or explicit `opCast` to an array;
- `opIndex`, `opSlice`, or `opDollar`;
- mutable byte view; or
- `length` property with an unstated unit.

Callers that deliberately need encoded storage use `.codeUnits` or `.bytes`.
The first preserves D's UTF-8 code-unit type; the second is an encoding-neutral
read-only byte view. Neither operation allocates.

## Construction and conversion

Construction policy depends on who controls the input:

| Source | API | Failure policy |
| --- | --- | --- |
| programmer-authored `const(char)[]` or literal | `String(utf8)` | panic on malformed UTF-8 |
| untrusted `const(char)[]` | `asString(candidate)` | `Utf8StringResult` |
| untrusted `const(u8)[]` | `asString(bytes)` | `Utf8StringResult` |
| audited, already validated code units | `asStringUnchecked(codeUnits)` | caller proof obligation |
| audited, already validated bytes | `asStringUnchecked(bytes)` | caller proof obligation |
| existing `String` | ordinary value copy | infallible |

```d
struct Utf8StringResult
{
    String value;
    Utf8Error error;

    bool succeeded() const pure @safe;
    bool failed() const pure @safe;
}

Utf8StringResult asString(
    return scope const(char)[] candidate,
) pure @trusted;

Utf8StringResult asString(
    return scope const(u8)[] bytes,
) pure @trusted;

String asStringUnchecked(
    return scope const(char)[] codeUnits,
) pure @system;

String asStringUnchecked(
    return scope const(u8)[] bytes,
) pure @system;
```

`Utf8StringResult.value` borrows the input on success and is `String.init` on
failure. `return scope` expresses this lifetime. The unchecked overloads are
`@system` because they can violate the central validity invariant even though
the slice cast itself does not immediately access invalid memory.

There is no conversion from arbitrary bytes that returns `String` directly.
There is also no implicit conversion from `String` to `const(char)[]`:
`alias this` would forward indexing, slicing, and unrelated array APIs to the
storage and defeat the wrapper.

### Literal ergonomics

D permits a converting struct constructor during initialization:

```d
String label = "network";
```

It does not apply that constructor when matching an ordinary function
parameter. Such calls are explicit:

```d
consume(String("network"));
```

This behavior was verified with the project's LDC 1.41 BetterC toolchain. Do
not add broad `const(char)[]` overloads to every API merely to conceal this D
rule. Formatting and logging APIs that are already templates may accept string
literals directly and construct a checked `String` internally, but ordinary
domain APIs continue to require `String`.

A future compile-time literal helper may eliminate runtime validation for
static text. It must reject malformed `\xNN` sequences at compile time and must
not become an unchecked path for runtime slices.

## Byte and scalar semantics

`char` is one UTF-8 code unit. `dchar` represents one Unicode scalar value in
this API. `u8` represents an encoding-neutral byte. These types are physically
compatible where conversion is needed, but they communicate different intent.

For `String text = String("Aé🙂")`:

```d
assert(text.byteLength == 7);
assert(text.codePointCount == 3);
assert(text.codeUnitAt(1) == cast(char) 0xC3);

foreach (dchar codePoint; text.codePoints)
    consumeCodePoint(codePoint);

foreach (decoded; text.codePointsWithOffsets)
    consumeSpan(decoded.byteOffset, decoded.byteLength, decoded.value);
```

All positions accepted or returned by string searching, slicing, and mutation
are byte offsets. Parameter and local names say `byteOffset`. There is no scalar
subscript because locating the Nth scalar is O(bytes); callers traverse
`codePoints` instead.

`sliceBytes`, `prefixBytes`, and `suffixBytes` panic if an offset is out of
bounds or not on a code-point boundary. They never round implicitly. Byte-budget
code first calls `floorCodePointBoundary` or `ceilCodePointBoundary`.

Code-point operations do not imply grapheme-cluster, normalization, collation,
case-folding, or display-width semantics.

## Equality, ordering, and hashing

Equality, `compare`, and hashing operate on the exact UTF-8 bytes. They do not
normalize. This is deterministic and keeps `toHash` consistent with
`opEquals`.

`String` compares with another `String` and with `const(char)[]` so literals are
ergonomic:

```d
String name = String("Ada");
assert(name == "Ada");
assert("Ada" == name);
```

The literal/slice overload compares code units directly; it does not construct
or bless another `String`. A valid `String` cannot compare equal to a malformed
nonempty UTF-8 sequence, so validation would only add cost without changing the
answer. Mixed equality must be tested in both operand orders. Arbitrary `u8`
binary data is not accepted by equality; callers compare `.bytes` explicitly
when that is the intended domain.

Lexicographic `compare` is encoded-byte ordering. It is not locale collation.
For valid UTF-8 it agrees with scalar-value order, but normalization-equivalent
strings can still compare unequal.

## `StringBuf` integration

`StringBuf` remains the non-copyable owning mutable UTF-8 builder. Its public
queries use explicit units:

```d
struct StringBuf
{
    static StringBuf create(Allocator* allocator);
    static StringBuf withCapacity(Allocator* allocator, size_t byteCapacity);
    static StringBuf fromString(Allocator* allocator, String value);

    size_t byteLength() const pure @safe;
    size_t byteCapacity() const pure @safe;
    bool empty() const pure @safe;
    String view() const return scope pure @safe;
    Allocator* allocator() return @safe;

    @disable this(this);
}

void append(ref StringBuf buffer, String value);
bool tryAppend(ref StringBuf buffer, String value);

void append(ref StringBuf buffer, char ascii);
bool tryAppend(ref StringBuf buffer, char ascii);

void append(ref StringBuf buffer, dchar codePoint);
bool tryAppend(ref StringBuf buffer, dchar codePoint);

void insert(ref StringBuf buffer, size_t byteOffset, String value);
bool tryInsert(ref StringBuf buffer, size_t byteOffset, String value);

void truncateBytes(ref StringBuf buffer, size_t newByteLength);
void clear(ref StringBuf buffer);
void resetAndRelease(ref StringBuf buffer);
```

The `char` overload accepts ASCII only. A non-ASCII scalar uses `dchar`; valid
multi-code-point text uses `String`. Edit and truncation offsets must be
code-point boundaries.

`view` constructs `String` through a package-private unchecked primitive because
all public `StringBuf` mutation preserves validity. No mutable slice escapes.
`StringBuf.fromBytesUnchecked` may remain as an explicitly `@system` audited
constructor, but malformed input violates the resulting buffer contract;
arbitrary binary ownership uses `Array!u8`.

## Module organization

The new dependency arrangement is:

```text
xtb.core.types    primitive numeric aliases only
       |
xtb.core.utf8     raw validation, decoding, encoding, range machinery
       |
xtb.core.string   String, Utf8StringResult, StringBuf, text algorithms
```

`xtb.core.types` no longer declares `String`. `xtb.core.utf8` operates on raw
`const(char)[]` and `const(u8)[]` only where malformed input is intentionally
part of the validation/decoding API. It does not import `xtb.core.string`.

`xtb.core.string` imports the UTF-8 primitives and owns the validity-preserving
wrapper. `CodePointRange` and `CodePointOffsetRange` may store raw private code
units internally, but user code can construct them only from a valid `String`.
This direction avoids a module cycle.

Moving `String` from `xtb.core.types` is a deliberate source-breaking change.
Public umbrella modules continue to re-export it, while implementation modules
must import `xtb.core.string : String` explicitly. Foreign ABIs never pass the
D struct directly; they continue to use the foreign API's pointer/length or
NUL-terminated representation.

## Implementation requirements

Before implementation is complete:

- compiler tests must prove borrowed results cannot escape their source;
- `String.sizeof` must equal `const(char)[].sizeof` and copying must remain
  trivial;
- no public operation may expose `codeUnits_` mutably;
- no ordinary constructor may create malformed UTF-8;
- unchecked construction must be isolated and audited;
- all existing ambiguous `.length`, indexing, slicing, and edit call sites must
  migrate to explicit byte APIs; and
- debug, optimized, release, sanitizer, examples, and unsupported-platform
  BetterC builds must pass.
