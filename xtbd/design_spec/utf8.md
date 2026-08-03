# UTF-8 design specification

## Status and scope

This document is the implementation contract for validated UTF-8 and Unicode
scalar traversal in xtb. The implementation belongs in `xtb.core.utf8` and must
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

`String` is the distinct borrowed UTF-8 view specified in
[`string.md`](string.md); `StringBuf` is the owning mutable UTF-8 builder. The
wrapper prevents ordinary integer indexing and built-in slicing from bypassing
UTF-8 boundaries. It exposes encoded storage only through explicit
`.codeUnits` and `.bytes` views.

The library distinguishes three units and never calls them all "characters":

| Unit | D representation | Size | xtb operation |
| --- | --- | --- | --- |
| UTF-8 code unit | `char` | exactly 1 byte | `codeUnits`, `codeUnitAt` |
| Encoding-neutral byte | `u8` | exactly 1 byte | binary and foreign I/O |
| Unicode scalar value / code point | `dchar` | encoded as 1 through 4 bytes | `codePoints`, `codePointCount` |
| Extended grapheme cluster | no core type yet | one or more code points | intentionally unsupported in this milestone |

`String.byteLength`, `StringBuf.byteLength`, and
`StringBuf.byteCapacity` are byte quantities. Every text position is a byte
offset unless an API explicitly states otherwise. Equality, hashing, ordering,
searching, and pattern lengths operate on encoded bytes and do not normalize
text. Embedded NUL is valid UTF-8 and remains one byte of the string.

This follows the useful parts of Rust's
[`str`](https://doc.rust-lang.org/stable/std/primitive.str.html): length and
search positions are bytes, substring boundaries preserve UTF-8, and scalar
traversal is separate from encoded-byte access. Unlike the earlier slice alias,
the new `String` can enforce those restrictions in its public interface.

The validity model is:

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

Add one focused module and re-export the stable text surface from
`xtb.core.package`:

```text
source/xtb/core/
├── types.d       # primitive numeric aliases only
├── utf8.d        # raw validation, decoding, encoding, range machinery
├── string.d      # String, checked conversion, algorithms, and StringBuf
└── package.d     # stable public re-exports
```

`xtb.core.utf8` imports primitive aliases from `xtb.core.types` and accepts raw
code-unit or byte slices only in APIs whose purpose is validation or safe
decoding of potentially malformed input. It must not import
`xtb.core.string`; this keeps the decoding primitive independent and prevents
a module cycle. `xtb.core.string` imports UTF-8 primitives to implement the
validated `String` wrapper, traversal members, and safe `StringBuf` mutations.

Serde, printing, and OS boundary modules consume `xtb.core.utf8`; they must not
retain private copies of UTF-8 decoders.

## Public error model

Malformed external text is expected input failure, not a panic. Validation and
single-code-point decoding return this concrete status:

Validation and decoding functions name their raw code-unit parameter
`candidate`: these are the deliberate APIs in which malformed text is accepted
as input. Ordinary string functions receive the validated `String` wrapper.

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
use `require`. Boundary predicates are the deliberate exception:
`isCodePointBoundary` returns `false` for an out-of-range offset, matching its
role as a checked query. Invalid bytes found at a valid decoding offset return
`Utf8Error`. This keeps API misuse distinct from untrusted input.

## Proposed public API

The public surface has this shape. All functions are `nothrow @nogc`. Pure
validation and value operations are `pure @safe`; operations that enforce a
programmer contract through the project's panic machinery cannot claim purity.

```d
module xtb.core.utf8;

nothrow @nogc:

import xtb.core.types : u8;

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

struct DecodedCodePoint
{
    dchar value;
    size_t byteOffset;
    u8 byteLength;
}

struct EncodedCodePoint
{
    private char[4] codeUnits_;
    private u8 byteLength_;

    const(char)[] codeUnits() const return scope pure @safe;
    u8 byteLength() const pure @safe;
}

Utf8Error validateUtf8(scope const(char)[] candidate) pure @safe;
Utf8Error validateUtf8(scope const(u8)[] candidate) pure @safe;

bool isValidUtf8(scope const(char)[] candidate) pure @safe;
bool isValidUtf8(scope const(u8)[] candidate) pure @safe;

Utf8Error decodeCodePoint(
    scope const(char)[] candidate,
    size_t byteOffset,
    DecodedCodePoint* output,
) @safe;

Utf8Error decodePreviousCodePoint(
    scope const(char)[] candidate,
    size_t endByteOffset,
    DecodedCodePoint* output,
) @safe;

bool isUnicodeScalar(dchar value) pure @safe;
bool tryEncodeUtf8(dchar value, EncodedCodePoint* output) @safe;
EncodedCodePoint encodeUtf8(dchar value) @safe;
u8 encodedUtf8Length(dchar value) @safe;

struct CodePointRange
{
    bool empty() const pure @safe;
    dchar front() const @safe;
    dchar back() const @safe;
    void popFront() @safe;
    void popBack() @safe;
    CodePointRange save() const pure @safe;
}

struct CodePointOffsetRange
{
    bool empty() const pure @safe;
    DecodedCodePoint front() const @safe;
    DecodedCodePoint back() const @safe;
    void popFront() @safe;
    void popBack() @safe;
    CodePointOffsetRange save() const pure @safe;
}
```

Checked `String` construction, unchecked conversion, boundary queries,
counting, and range construction are exposed through `xtb.core.string` as
specified in [`string.md`](string.md). Raw helpers used only to implement those
members remain package-private.

The API deliberately does not introduce a universal `Result!T`. The specific
`Utf8StringResult` in `xtb.core.string` exists because it must return both a
borrowed view and a validation status while preserving the input lifetime in
the returned value.
No caller-owned object is being mutated, so returning this small descriptor is
consistent with the pointer-for-mutation rule.

`Utf8StringResult.value` is the borrowed input view on success and `String.init`
on failure. It owns nothing and has exactly the source byte slice's lifetime.
The `return scope` input expresses that relationship under DIP1000. A compile-
time regression test must prove both sides: returning the result from a
`return scope` source is accepted, while attempting to return it from an
ordinary `scope` source is rejected. Do not weaken this with an escaping cast.

`DecodedCodePoint*` and `EncodedCodePoint*` are required non-null output
pointers. Each function clears its output before examining input and leaves it
zeroed on recoverable failure. This follows the project's explicit mutation
convention.

`encodeUtf8` and `encodedUtf8Length` require a valid Unicode scalar and panic on
contract violation. `tryEncodeUtf8` returns `false` for a surrogate or value
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
`0 < endByteOffset && endByteOffset <= candidate.length`. It scans backward by
at most four bytes, then validates the complete sequence and requires it to end
exactly at `endByteOffset`.

Both functions are safe on malformed input and report a recoverable error. They
never assume alignment and never read outside the supplied slice. This makes
them suitable for parsers that need an error offset without validating the
entire document first.

`String.isCodePointBoundary(byteOffset)` follows Rust's useful checked-query
semantics: zero and `value.byteLength` are boundaries, an interior offset is a
boundary exactly when its byte is not a continuation byte, and an offset
greater than `value.byteLength` returns `false` rather than panicking. The
operation is constant time. Raw input that may be malformed is validated first.

`floorCodePointBoundary` and `ceilCodePointBoundary` support byte budgets
without splitting an encoding. Both clamp an offset greater than
`value.byteLength` to `value.byteLength`. The floor operation returns the
nearest boundary at or below the clamped offset; the ceiling operation returns
the nearest boundary at or above it. They inspect at most three adjacent bytes
for valid UTF-8 and are therefore O(1). They do not preserve grapheme clusters:
rounding a byte budget may still separate a combining mark or a joined emoji
sequence.

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
    use(decoded.byteOffset, decoded.value, decoded.byteLength);
```

`CodePointRange` is a copyable, non-owning bidirectional cursor over a `String`.
It stores only the remaining byte slice. Copying or `save` creates an independent
cursor over the same borrowed storage. It allocates nothing.

The range follows D's `empty`, `front`, `popFront`, `back`, `popBack`, and
`save` conventions so it works with `foreach` without importing Phobos ranges.
The source bytes must outlive all copies. The range must never escape a shorter-
lived input, and DIP1000 attributes must express that borrowing relationship.

Traversal assumes the ordinary `String` contract. If unchecked invalid bytes
reach the range, `front`, `back`, or a pop operation panics instead of returning
a replacement character or reading invalid memory. Recoverable traversal of
untrusted bytes uses `decodeCodePoint` or validates once before constructing the
range.

`CodePointOffsetRange` has the same ownership, validity, direction, and panic
contracts, but yields `DecodedCodePoint`. Its `byteOffset` is always relative to
the beginning of the original `String`, including during reverse traversal or
after either end of the range has advanced. This is xtb's code-point-named
equivalent of Rust's `char_indices`: the reported position is a byte offset,
not a scalar ordinal. `byteLength` makes the exact source span
`value.codeUnits[byteOffset .. byteOffset + byteLength]` available without
decoding the scalar again.

`String.codePointCount` traverses valid UTF-8 and returns the number of Unicode
scalar values. It is O(bytes), performs no allocation, and panics if the
`String` contract was violated. It is intentionally distinct from
`String.byteLength`.

Neither code-point count nor traversal represents user-perceived characters.
For example, a base character followed by a combining mark has two code points
but may form one grapheme cluster. The API must not call code points
"characters" in documentation or identifiers.

## Byte-addressed string operations

The UTF-8 milestone must audit `xtb.core.string`, not merely add a decoder.
Every public operation that exposes a unit follows these rules:

| Operation | Unit and result |
| --- | --- |
| `String.byteLength`, `StringBuf.byteLength`, `StringBuf.byteCapacity` | bytes |
| `find(String)`, `findLast(String)` | byte offset or `notFound` |
| `sliceBytes(beginByteOffset, endByteOffset)` | byte range whose endpoints must be code-point boundaries |
| `prefixBytes(endByteOffset)`, `suffixBytes(beginByteOffset)` | byte range ending or beginning at a code-point boundary |
| `frontByte`, `backByte`, `findCodeUnit(char)` | one UTF-8 code unit, with no scalar interpretation |
| `findCodePoint(dchar)` | byte offset of the encoded scalar or `notFound` |
| `codePointCount` | scalar count, computed in O(bytes) |
| `codePoints` | scalar traversal yielding `dchar` |
| `codePointsWithOffsets` | scalar traversal yielding the scalar and its byte span |

The current `slice`, `head`, `tail`, `truncateLeft`, `truncateRight`, `front`,
`back`, and `find(char)` names are too easy to read as scalar operations. During
implementation, replace them with the explicit byte/code-unit names above and
migrate all call sites in the same commit. Do not keep ambiguous aliases merely
for convenience. `find(String)` and `findLast(String)` may keep their familiar
names, following Rust's precedent, but their documentation and local result
variables must say that the result is a byte offset.

`sliceBytes`, `prefixBytes`, and `suffixBytes` are O(1). They panic when an
offset is out of range or falls inside an encoded scalar; they never round
silently. Callers deliberately implementing a byte budget first call
`floorCodePointBoundary` or `ceilCodePointBoundary`, which makes the rounding
policy visible:

```d
const endByteOffset = text.floorCodePointBoundary(maxBytes);
String prefix = text.prefixBytes(endByteOffset);
```

There is no general scalar subscript. If a caller needs the Nth scalar, it
advances `codePoints` and thereby exposes the O(bytes) cost. A future helper may
be named `codePointAt` and must document that cost; it must not accept or return
an unqualified `index`.

All `StringBuf` edit offsets are bytes and use `byteOffset` in signatures and
local variables. Insertion, truncation, removal, and replacement must preserve
UTF-8 validity by requiring boundaries at every cut. Operations that accept a
valid `String` pattern naturally cut only at boundaries; operations over raw
code units require special care and must not publish a malformed `StringBuf`.

## Encoding and `StringBuf`

`EncodedCodePoint` owns up to four inline code units and exposes only its
initialized prefix through `codeUnits`. It requires no allocator and prevents
callers from mistaking unused array bytes for encoded text.

`StringBuf` gains Unicode-scalar overloads:

```d
void append(ref StringBuf buffer, dchar value);
bool tryAppend(ref StringBuf buffer, dchar value);

void appendAssumeCapacity(ref StringBuf buffer, dchar value);
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

Public `appendByte` is misleading for a text builder and should be removed or
made package-private. Audited internals that fill already reserved storage may
use a clearly named unchecked helper, but arbitrary binary construction belongs
in `Array!u8`. `appendAssumeCapacity(char)` has the same ASCII precondition as
ordinary `append(char)`.

Operations accepting `String`--append, prepend, insert, replace, and
construction from `String`--assume their inputs already satisfy the `String`
contract and do not rescan them. Operations using a byte offset to create or
modify text must require a code-point boundary. This includes `sliceBytes`
endpoints and `StringBuf.insert` positions. Byte offsets returned by searching
valid UTF-8 for valid UTF-8 are safe boundaries because UTF-8 is self-
synchronizing.

Callers may explicitly slice `String.codeUnits`, and that raw slice can split a
sequence. It remains `const(char)[]`, not `String`. Checked conversion rejects a
split sequence; audited code may reconstruct `String` only after proving both
boundaries and validity.

## Interaction with existing modules

### Serde

JSON and TOML currently contain separate UTF-8 validators, width decoders, and
encoders. Replace them with `xtb.core.utf8` primitives. Both parsers continue to
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
non-NUL bytes. They cannot truthfully become ordinary `String` merely because
the platform exposes `char*`. They need a byte-oriented native representation
or an explicitly documented policy that rejects non-UTF-8 names. This is a
follow-up OS API concern, not a reason to weaken the text contract.

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

Use `require`/panic for violated programming contracts:

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

Tests live beside `xtb.core.utf8` for unit behavior, with integration cases in
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
  sequences and for offsets beyond the end;
- code-point count differing from byte length and from grapheme count;
- `StringBuf` scalar append at all widths, capacity boundaries, aliasing, and
  injected allocation failure;
- byte-indexed string/buffer operations accepting boundaries and rejecting
  split sequences;
- checked byte-to-`String` conversion preserving pointer, byte length, and
  lifetime without allocating;
- compile-time rejection of `String` indexing, built-in slicing, array
  conversion, and escape beyond the borrowed source;
- serde JSON and TOML using the shared implementation with unchanged error
  locations; and
- sanitizer runs over malformed and truncated buffers to establish that no
  decoder reads out of bounds.

The exhaustive scalar round trip is approximately 1.1 million small cases and
is suitable for the native test suite. Compile-time tests should also prove
that the range cannot escape shorter-lived storage and that production modules
continue to compile under `-betterC`.

## Implementation sequence

Implement this design in the following order:

1. Add error types, strict forward decoding, validation, and exhaustive tests.
2. Introduce the `String` wrapper, checked/unchecked borrowed conversion, and
   lifetime tests; migrate basic byte-oriented string operations.
3. Add reverse decoding, boundary queries, counting, `CodePointRange`, and
   `CodePointOffsetRange`.
4. Add scalar encoding and validity-preserving `StringBuf` operations while
   migrating its size and edit API to explicit byte names.
5. Replace the duplicated JSON, TOML, and printer UTF-8 implementations.
6. Audit foreign C-string producers and every remaining raw code-unit boundary.
7. Update architecture, testing documentation, README, and examples to
   describe the implemented API rather than the current provisional contract.

Each step must pass debug, optimized, release, sanitizer, and unsupported-
platform compile checks already used by the project before the next step is
committed.
