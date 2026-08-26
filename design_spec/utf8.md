# UTF-8 design specification

## Status and scope

This document is the implementation contract for validated UTF-8 and Unicode
scalar traversal in xtb. The implementation belongs in `xtb.utf8` and must
remain compatible with BetterC.

The module provides strict UTF-8 validation, checked byte-to-text conversion,
single-code-point decoding and encoding, boundary queries, code-point counting,
and allocation-free forward and reverse traversal. It also defines how these
operations strengthen the existing `String` and `StringBuf` contracts.

This milestone does not implement normalization, case conversion, locale-aware
comparison, grapheme clusters, display width, collation, or lossy decoding.
Those are separate Unicode features with substantially larger policy and data
requirements.

## Design constraints

The existing text model remains unchanged:

```d
alias String = const(char)[];
```

`String` is a borrowed read-only UTF-8 view and `StringBuf` is an owning mutable
UTF-8 buffer and builder. Both remain byte-addressed:

- `String.length` is a byte count;
- indexing yields a UTF-8 code unit, not a Unicode scalar value;
- byte equality, hashing, and searching do not normalize text;
- embedded NUL is valid UTF-8 and remains part of the string;
- code-point work is requested through explicitly named APIs.

The exact byte-oriented string surface and the intentionally unchecked parts
of the alias are specified in [`string.md`](string.md). This design follows
Rust's separation of encoded bytes, Unicode scalar values, and grapheme
clusters while preserving D literal interoperability.

Keeping `String` as an alias preserves literal interoperability, trivial copy
semantics, and temporary views into `StringBuf`. It also means the compiler
cannot attach a proof of UTF-8 validity to a value. A cast, built-in slice, or
unchecked conversion can always manufacture an invalid `String`.

The library therefore enforces a contract rather than claiming type-enforced
validity:

1. External bytes are validated before becoming ordinary text.
2. Ordinary text-producing operations preserve UTF-8 validity.
3. Explicitly unchecked APIs transfer the proof obligation to their caller.
4. Unicode operations detect invalid input safely; they never read beyond a
   slice or execute undefined behavior.

Validation is not repeated by every byte-preserving operation. Revalidating on
every append, comparison, or print would make ordinary composition needlessly
quadratic. Modules validate at trust boundaries and then preserve the contract.

The module must not use the GC, exceptions, classes, Phobos Unicode algorithms,
runtime reflection, hidden allocation, or process-global state. All operations
except mutation of an explicit `StringBuf` are allocation-free.

## Unicode model

The implementation accepts exactly Unicode scalar values encoded using strict
UTF-8:

- U+0000 through U+D7FF;
- U+E000 through U+10FFFF.

It rejects:

- isolated continuation bytes;
- invalid leading bytes, including `C0`, `C1`, and `F5` through `FF`;
- truncated sequences;
- non-continuation bytes where a continuation is required;
- overlong encodings;
- UTF-16 surrogate code points U+D800 through U+DFFF; and
- values greater than U+10FFFF.

The accepted byte forms are exact:

| Width | First byte | Second byte | Remaining bytes |
| --- | --- | --- | --- |
| 1 | `00`-`7F` | none | none |
| 2 | `C2`-`DF` | `80`-`BF` | none |
| 3 | `E0` | `A0`-`BF` | one `80`-`BF` |
| 3 | `E1`-`EC`, `EE`-`EF` | `80`-`BF` | one `80`-`BF` |
| 3 | `ED` | `80`-`9F` | one `80`-`BF` |
| 4 | `F0` | `90`-`BF` | two `80`-`BF` |
| 4 | `F1`-`F3` | `80`-`BF` | two `80`-`BF` |
| 4 | `F4` | `80`-`8F` | two `80`-`BF` |

Validation examines available bytes from left to right. A byte outside
`80`-`BF` in a continuation position is `invalidContinuation`. A continuation
inside that broad range but outside a restricted second-byte range is
`overlongEncoding`, `surrogateCodePoint`, or `codePointOutOfRange` as selected
by the table. `truncatedSequence` is reported only when the next required byte
does not exist and no earlier available byte has already made the sequence
invalid. This precedence makes inputs with more than one defect deterministic.

The byte-order mark U+FEFF and Unicode noncharacters are valid scalar values
and are accepted. The validator does not strip a byte-order mark or interpret
it as an endianness marker. It does not reject noncharacters, normalize text,
or silently replace malformed input.

## Module organization

Add one focused module and re-export it from `xtb.package`:

```text
source/xtb/core/
├── types.d       # String alias and primitive aliases
├── utf8.d        # validation, decoding, encoding, traversal
├── string.d      # String algorithms and StringBuf ownership/mutation
└── package.d     # stable public re-exports
```

`xtb.utf8` may import `String` and integer aliases from
`xtb.types`. It must not import `xtb.string`; this keeps the decoding
primitive independent and prevents a module cycle. `xtb.string` may import
UTF-8 encoding and boundary helpers to implement safe `StringBuf` mutations.

Serde, printing, and OS boundary modules consume `xtb.utf8`; they must not
retain private copies of UTF-8 decoders.

## Public error model

Malformed external text is expected input failure, not a panic. Validation and
single-code-point decoding return this concrete status:

Validation and decoding functions name their text parameter `candidate`: these
are the deliberate APIs in which a value spelled as `String` is not yet assumed
valid. Ordinary string functions continue to require valid UTF-8.

```d
enum Utf8ErrorKind : u8
{
    none,
    unexpectedContinuation,
    invalidLeadingByte,
    truncatedSequence,
    invalidContinuation,
    overlongEncoding,
    surrogateCodePoint,
    codePointOutOfRange,
}

struct Utf8Error
{
nothrow @nogc:

    Utf8ErrorKind kind;
    size_t byteOffset;

    bool succeeded() const pure @safe;
    bool failed() const pure @safe;
}
```

`Utf8Error.init` means success. `byteOffset` is defined precisely:

- for an unexpected continuation or invalid leading byte, it identifies that
  byte;
- for an invalid continuation, it identifies the byte that should have been a
  continuation;
- for a truncated sequence, it equals `input.length`, the position of the
  first missing byte;
- for an overlong encoding, surrogate, or out-of-range scalar, it identifies
  the leading byte of the invalid sequence.

The first invalid sequence in byte order is reported, using the classification
precedence above. Error categories and offsets are stable observable behavior
and require exact tests. A caller interested only in validity may use
`isValidUtf8`; parsers should retain `Utf8Error` so they can map its offset into
their own diagnostics.

Invalid offsets passed to decoding or mutating APIs are programmer errors and
use `require`. `isCodePointBoundary` is the deliberate checked-query exception
and returns `false` beyond the end. Invalid bytes found at a valid decoding
offset return `Utf8Error`. This keeps API misuse distinct from untrusted input.

## Public API

The public surface has this shape. All functions are `nothrow @nogc`. Pure
validation and value operations are `pure @safe`; operations that enforce a
programmer contract through the project's panic machinery cannot claim purity.

```d
module xtb.utf8;

nothrow @nogc:

public import xtb.types : String;
import xtb.types : u8;

enum Utf8ErrorKind : u8
{
    none,
    unexpectedContinuation,
    invalidLeadingByte,
    truncatedSequence,
    invalidContinuation,
    overlongEncoding,
    surrogateCodePoint,
    codePointOutOfRange,
}

struct Utf8Error
{
    Utf8ErrorKind kind;
    size_t byteOffset;

    bool succeeded() const pure @safe;
    bool failed() const pure @safe;
}

struct Utf8StringResult
{
    String value;
    Utf8Error error;

    bool succeeded() const pure @safe;
    bool failed() const pure @safe;
}

struct DecodedCodePoint
{
    dchar value;
    size_t byteOffset;
    u8 byteLength;
}

struct EncodedCodePoint
{
    private char[4] bytes_;
    private u8 byteLength_;

    char[4] codeUnits() const pure @safe;
    u8 byteLength() const pure @safe;
}

Utf8Error validateUtf8(scope String candidate) @safe;
Utf8Error validateUtf8(scope const(u8)[] candidate) @trusted;

bool isValidUtf8(scope String candidate) @safe;
bool isValidUtf8(scope const(u8)[] candidate) @trusted;

Utf8StringResult asString(return scope const(u8)[] bytes) @trusted;

Utf8Error decodeCodePoint(
    scope String candidate,
    size_t byteOffset,
    scope DecodedCodePoint* output,
) @safe;

Utf8Error decodePreviousCodePoint(
    scope String candidate,
    size_t endByteOffset,
    scope DecodedCodePoint* output,
) @safe;

bool isCodePointBoundary(
    scope String value,
    size_t byteOffset,
) @safe;

size_t floorCodePointBoundary(
    scope String value,
    size_t byteOffset,
) @safe;

size_t ceilCodePointBoundary(
    scope String value,
    size_t byteOffset,
) @safe;

bool isUnicodeScalar(dchar value) pure @safe;
bool tryEncodeUtf8(dchar value, scope EncodedCodePoint* output) @safe;
EncodedCodePoint encodeUtf8(dchar value) @safe;
u8 encodedUtf8Length(dchar value) @safe;

size_t codePointCount(scope String value) @safe;

struct CodePointRange
{
    bool empty() const pure @safe;
    dchar front() const @safe;
    dchar back() const @safe;
    void popFront() @safe;
    void popBack() @safe;
    CodePointRange save() const pure @safe;
    int opApply(
        scope int delegate(dchar) nothrow @nogc @safe callback,
    ) const @safe;
    int opApply(
        scope int delegate(dchar) nothrow @nogc @system callback,
    ) const @system;
}

CodePointRange codePoints(return scope String value) pure @safe;

struct CodePointOffsetRange
{
    bool empty() const pure @safe;
    DecodedCodePoint front() const @safe;
    DecodedCodePoint back() const @safe;
    void popFront() @safe;
    void popBack() @safe;
    CodePointOffsetRange save() const pure @safe;
    int opApply(
        scope int delegate(DecodedCodePoint) nothrow @nogc @safe callback,
    ) const @safe;
    int opApply(
        scope int delegate(DecodedCodePoint) nothrow @nogc @system callback,
    ) const @system;
}

CodePointOffsetRange codePointsWithOffsets(
    return scope String value,
) pure @safe;
```

The API deliberately does not introduce a universal `Result!T`. The specific
`Utf8StringResult` exists because it must return both a borrowed view and a
validation status while preserving the input lifetime in the returned value.
No caller-owned object is being mutated, so returning this small descriptor is
consistent with the pointer-for-mutation rule.

`Utf8StringResult.value` is the borrowed input view on success and `String.init`
on failure. It owns nothing and has exactly the source byte slice's lifetime.
The `return scope` input expresses that relationship under DIP1000. A compile-
`return scope` documents the source relationship and preserves it where D can
track a direct return. DIP1000 does not propagate lifetimes through fields of a
returned aggregate, however, so it cannot reject every escape of
`Utf8StringResult.value`, `CodePointRange`, or `CodePointOffsetRange`. This is a
language limitation, not a claim of ownership: callers must still keep the
source alive. Compile-time tests cover the relationships D can express, and
runtime/API documentation must not promise Rust-style borrow checking here.

`DecodedCodePoint*` and `EncodedCodePoint*` are required non-null output
pointers. Each function clears its output before examining input and leaves it
zeroed on recoverable failure. This follows the project's explicit mutation
convention.

`encodeUtf8` and `encodedUtf8Length` require a valid Unicode scalar.
`tryEncodeUtf8` returns `false` for a surrogate or value
above U+10FFFF. Encoding never substitutes U+FFFD implicitly.

## Checked byte-to-text conversion

Raw bytes use `const(u8)[]`; validated text uses `String`. The normal boundary
conversion is:

```d
const(u8)[] response = receiveBytes();
const checked = response.asString();
if (checked.failed)
{
    reportInvalidText(checked.error.kind, checked.error.byteOffset);
    return;
}

consumeText(checked.value);
```

The conversion validates once and returns a borrowed view without allocating.
If a mutable alias to the bytes exists, the caller must not mutate them while
the `String` is in use. Validation cannot turn mutable external storage into
immutable storage.

The unchecked operations remain available for audited low-level code:

```d
String trusted = bytes.asStringUnchecked();
StringBuf exactCopy = StringBuf.fromBytesUnchecked(allocator, bytes);
```

Their names must remain visibly unchecked. They neither validate nor promise
that the implementation established validity; the caller must already have
that proof. Passing malformed data violates the `String`/`StringBuf` contract.
`fromBytesUnchecked` is not permission to use `StringBuf` as raw storage, and
existing tests that present malformed bytes as a supported owned-string state
must be replaced. Binary APIs use `Array!u8`, not this escape hatch.

There is no combined allocating `StringBuf.fromBytes` in the first milestone.
It would have to report two independent expected failures--invalid encoding and
allocation--without an established common error type. The explicit composition
keeps those failure domains clear:

```d
const checked = bytes.asString();
if (checked.failed)
    return TextLoadError.invalidEncoding(checked.error);

StringBuf owned;
if (!StringBuf.tryFromString(allocator, checked.value, &owned))
    return TextLoadError.allocationFailed();
```

A convenience constructor may be added later alongside a concrete consumer and
a domain-appropriate error type. It must not collapse malformed input and
allocation failure into one Boolean.

## Decoding and offsets

`decodeCodePoint(candidate, byteOffset, output)` decodes the sequence beginning
at `byteOffset`. It requires `byteOffset < candidate.length`. On success,
`output.byteOffset == byteOffset` and `output.byteLength` is between one and
four.

`decodePreviousCodePoint(candidate, endByteOffset, output)` decodes the sequence
ending immediately before `endByteOffset`. It requires
`0 < endByteOffset && endByteOffset <= candidate.length`. It scans backward by at most
four bytes, then validates the complete sequence and requires it to end exactly
at `endByteOffset`.

Both functions are safe on malformed input and report a recoverable error. They
never assume alignment and never read outside the supplied slice. This makes
them suitable for parsers that need an error offset without validating the
entire document first.

`isCodePointBoundary(value, byteOffset)` follows Rust's query semantics: zero
and `value.length` are boundaries, an interior offset is a boundary exactly
when its byte is not a continuation byte, and an offset beyond the end returns
`false`. The operation is O(1). When input may be malformed, validate it first.

`floorCodePointBoundary` and `ceilCodePointBoundary` clamp an offset beyond the
end to `value.length`, then return the nearest boundary at or below/above it.
They inspect at most three adjacent bytes and are O(1) for valid UTF-8. These
operations preserve scalar encodings, not grapheme clusters.

## Traversal

Code-point traversal is explicit:

```d
String text = "Aé🙂";

foreach (dchar codePoint; text.codePoints)
    use(codePoint);

auto range = text.codePoints;
while (!range.empty)
{
    use(range.back);
    range.popBack();
}

foreach (decoded; text.codePointsWithOffsets)
    use(decoded.byteOffset, decoded.byteLength, decoded.value);
```

`CodePointRange` is a copyable, non-owning bidirectional cursor over a `String`.
It stores only the remaining byte slice. Copying or `save` creates an independent
cursor over the same borrowed storage. It allocates nothing.

The range follows D's `empty`, `front`, `popFront`, `back`, `popBack`, and
`save` conventions for manual/range-style use. Its allocation-free `opApply`
overloads provide language-level `foreach` for both safe and system callbacks
without importing Phobos ranges.
The source bytes must outlive all copies. `return scope` expresses the intended
borrowing relationship, but DIP1000 cannot prevent a borrowed slice stored in
a returned range aggregate from escaping. Callers must not return or retain a
range beyond its source.

Traversal assumes the ordinary `String` contract. Passing unchecked invalid
bytes to the range violates that precondition; traversal never substitutes a
replacement character. Recoverable traversal of untrusted bytes uses
`decodeCodePoint` or validates once before constructing the range.

`CodePointOffsetRange` has the same borrowing and traversal contract but yields
`DecodedCodePoint`. Its offsets remain relative to the original `String`, even
during reverse traversal or after either end advances. This is the
code-point-named equivalent of Rust's `char_indices`; the index is a byte
offset, not a scalar ordinal.

`codePointCount` traverses valid UTF-8 and returns the number of Unicode scalar
values. It is O(bytes), performs no allocation, and requires the ordinary
`String` validity contract. It is intentionally distinct from `String.length`.

Neither code-point count nor traversal represents user-perceived characters.
For example, a base character followed by a combining mark has two code points
but may form one grapheme cluster. The API must not call code points
"characters" in documentation or identifiers.

## Encoding and `StringBuf`

`EncodedCodePoint` owns up to four inline bytes. `codeUnits` returns its complete
four-byte storage by value and `byteLength` identifies the initialized prefix.
Returning the array by value avoids a slice that could outlive a temporary
`EncodedCodePoint`. It requires no allocator.

`StringBuf` gains Unicode-scalar overloads:

```d
struct StringBuf
{
    void append(dchar value);
    bool tryAppend(dchar value);
    void appendAssumeCapacity(dchar value);
}
```

These functions require `isUnicodeScalar(value)`. The fallible overload returns
`false` only for allocation failure; an invalid scalar remains a contract
violation rather than sharing that Boolean. The append reserves enough space
before changing the logical length and publishes all encoded bytes together.

The existing `char` append overload represents one ASCII code point. It must
require a value no greater than `0x7F`. A D `char` is a UTF-8 code unit, not a
Unicode scalar, so appending an arbitrary high byte could leave the buffer
malformed. Non-ASCII values are appended as `dchar` or as an already valid
`String`.

Public `appendByte` is removed because it is misleading for a text builder.
Audited internals such as `Writer` preserve code-point boundaries, convert each
independently valid byte chunk with `asStringUnchecked`, and use the ordinary
`append(String)` or `tryAppend(String)` member. Arbitrary binary construction
belongs in `Array!u8`. `appendAssumeCapacity(char)` has the same ASCII
precondition as ordinary `append(char)`.

Operations accepting `String`--append, prepend, insert, replace, and
construction from `String`--assume their inputs already satisfy the `String`
contract and do not rescan them. Operations using a byte offset to create or
modify text must require a code-point boundary. This includes `sliceBytes`
endpoints and `StringBuf.insert` positions. Byte offsets returned by searching
valid UTF-8 for valid UTF-8 are safe boundaries because UTF-8 is self-
synchronizing.

D's built-in slicing remains capable of splitting a sequence. Such a slice is
an unchecked value, just like a cast from bytes; the caller must not pass it as
ordinary `String` until its boundaries and validity are established. The
library cannot prevent this without replacing the required `String` alias.

## Interaction with existing modules

### Serde

JSON and TOML currently contain separate UTF-8 validators, width decoders, and
encoders. Replace them with `xtb.utf8` primitives. Both parsers continue to
map malformed text to `SerdeErrorKind.invalidUtf8` at the exact source offset.
Escaped Unicode scalars are encoded with the shared encoder after the existing
JSON surrogate-pair or TOML escape rules have produced a scalar value.

Serialization validates user-provided `String` fields at the backend boundary
and reports the existing serde error rather than panicking. This is appropriate
because schema values can originate from unchecked or foreign storage.

### Printing

Printing `String` writes its bytes directly and assumes valid UTF-8. Printing a
`dchar` uses the shared encoder. The current behavior that silently converts an
invalid `dchar` to U+FFFD should be removed; replacement is a policy decision,
not core encoding.

Printer literal fragments and ASCII punctuation are known-valid producers.
Writer sinks must become explicitly byte-oriented (`scope const(u8)[]`) because
buffer flushing and partial OS writes can divide a stream at any byte. A sink
chunk must not be mislabeled as an independently valid `String`.

The package-private `StringBuf` sink may append those raw chunks while a writer
call is in progress, but no invalid intermediate view may escape. A fallible
owned formatting operation destroys its output on sink failure; a successful
operation finishes with valid UTF-8. Fixed-buffer text formatting must truncate
at the last complete code-point boundary while retaining the exact required
byte count. It must never return a successful-looking text prefix ending in a
partial sequence.

### C and operating-system boundaries

A `const(char)*` does not imply UTF-8. General C-string conversion must either
validate and return `Utf8Error` or be named `fromCStringUnchecked`. Existing
uses of `fromCString` require an audit rather than being silently declared safe.

POSIX paths, environment entries, and directory names may contain arbitrary
non-NUL bytes. The current text-oriented OS API deliberately rejects malformed
UTF-8 as `OsErrorKind.invalidData`; it never relabels those bytes as `String`.
A future byte-oriented native path API may broaden platform coverage without
weakening the text contract.

Process stdout and stderr remain binary `u8` buffers. A caller explicitly uses
checked `asString` before treating captured output as text. The existing
`asStringUnchecked` remains available when an external protocol already proves
the encoding.

### Existing string algorithms

Byte-oriented equality, comparison, hashing, finding, prefix/suffix checks,
ASCII whitespace trimming, and escaping retain their current semantics. They
do not normalize or decode code points. Their documentation should use
"byte", "code unit", or "ASCII" precisely.

Any algorithm advertised as Unicode-aware must be implemented using this module
and named accordingly. ASCII-only transformations remain useful and should not
be renamed to imply full Unicode behavior.

## Failure and panic policy

Use recoverable status for data that can be malformed at a trust boundary:

- validating external bytes;
- decoding a sequence from a parser cursor;
- validating text supplied to a serializer;
- converting foreign output into text.

Use a call-site-guarded `require` for violated programming contracts in
checked builds:

```d
version (XTB_Checked)
    require(condition, "contract violation");
```

Release-fast treats the same conditions as caller preconditions. Examples:

- a null required output pointer;
- an offset outside its documented range;
- traversing a code-point range over a `String` previously obtained through an
  unchecked path without validating it;
- appending a non-ASCII `char` as though it were a complete code point;
- passing a surrogate or out-of-range value to the non-fallible encoder.

No API performs lossy recovery implicitly. A future lossy decoder must be
explicitly named, document the maximal-invalid-subpart policy it follows, and
report whether replacements occurred.

## Testing requirements

Tests live beside `xtb.utf8` for unit behavior, with integration cases in
serde, printing, strings, and process examples where appropriate. At minimum,
cover:

- empty input, ASCII, embedded NUL, and mixed one- through four-byte text;
- the minimum and maximum scalar encoded at every UTF-8 width;
- U+D7FF, U+E000, U+10FFFF, U+FEFF, and accepted noncharacters;
- every possible single leading byte classification;
- isolated continuation bytes at every position;
- every truncation length for two-, three-, and four-byte sequences;
- invalid continuation bytes in every continuation position;
- all overlong forms, surrogate encodings, and values above U+10FFFF;
- exact error kind and byte offset after a valid prefix;
- forward and reverse decoding of the same string;
- forward and reverse range iteration, empty ranges, copied ranges, and early
  `break` from `foreach`;
- every legal scalar value round-tripped through encode and decode;
- invalid `dchar` values rejected without partially modifying output;
- code-point boundary checks at zero, end, every leading byte, and every
  continuation byte;
- floor/ceiling boundary rounding at every byte of one- through four-byte
  sequences and beyond the end;
- code-point count differing from byte length and from grapheme count;
- offset-producing traversal in both directions with offsets relative to the
  original string;
- `StringBuf` scalar append at all widths, capacity boundaries, aliasing, and
  injected allocation failure;
- byte-indexed string/buffer operations accepting boundaries and rejecting
  split sequences;
- checked byte-to-`String` conversion preserving pointer and length without
  allocating, plus compile-time coverage of every lifetime relationship that
  DIP1000 can represent;
- serde JSON and TOML using the shared implementation with unchanged error
  locations; and
- sanitizer runs over malformed and truncated buffers to establish that no
  decoder reads out of bounds.

The exhaustive scalar round trip is approximately 1.1 million small cases and
is suitable for the native test suite. Compile-time tests cover direct
`return scope` propagation; aggregate-contained borrows remain a documented
caller obligation. Production modules continue to compile under `-betterC`.

## Implemented sequence

The implementation was completed in this order:

1. Add error types, strict forward decoding, validation, and exhaustive tests.
2. Add reverse decoding, boundary queries, counting, and `CodePointRange`.
3. Add scalar encoding and `StringBuf` scalar append operations.
4. Add checked borrowed byte-to-text conversion and lifetime tests.
5. Replace the duplicated JSON, TOML, and printer UTF-8 implementations.
6. Audit string slicing/mutation boundaries and foreign C-string producers.
7. Update architecture, testing documentation, and examples to describe the
   implemented API rather than the current provisional contract.

The complete result passes debug, optimized, release, sanitizer, and
unsupported-platform compile checks in the standard project gate.
