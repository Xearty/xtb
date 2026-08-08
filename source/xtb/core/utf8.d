module xtb.core.utf8;

nothrow @nogc:

public import xtb.core.types : String;

version (XTB_Checked) import xtb.core.panic : require;
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
nothrow @nogc:

    Utf8ErrorKind kind;
    size_t byteOffset;

    bool succeeded() const pure @safe
    {
        return kind == Utf8ErrorKind.none;
    }

    bool failed() const pure @safe
    {
        return !succeeded;
    }
}

struct Utf8StringResult
{
nothrow @nogc:

    String value;
    Utf8Error error;

    bool succeeded() const pure @safe
    {
        return error.succeeded;
    }

    bool failed() const pure @safe
    {
        return error.failed;
    }
}

struct DecodedCodePoint
{
    dchar value;
    size_t byteOffset;
    u8 byteLength;
}

struct EncodedCodePoint
{
nothrow @nogc:

    private char[4] bytes_;
    private u8 byteLength_;

    char[4] codeUnits() const pure @safe
    {
        return bytes_;
    }

    u8 byteLength() const pure @safe
    {
        return byteLength_;
    }
}

private Utf8Error utf8Error(Utf8ErrorKind kind, size_t byteOffset)
pure @safe
{
    return Utf8Error(kind, byteOffset);
}

private bool isContinuation(u8 value) pure @safe
{
    return (value & 0xc0) == 0x80;
}

Utf8Error decodeCodePoint(
    scope String candidate,
    size_t byteOffset,
    scope DecodedCodePoint* output,
) @safe
{
    version (XTB_Checked)
        require(output !is null, "decoded code point output is null");
    *output = DecodedCodePoint.init;
    version (XTB_Checked)
        require(byteOffset < candidate.length, "UTF-8 byte offset out of bounds");

    const first = cast(u8) candidate[byteOffset];
    if (first <= 0x7f)
    {
        *output = DecodedCodePoint(cast(dchar) first, byteOffset, 1);
        return Utf8Error.init;
    }
    if (first >= 0x80 && first <= 0xbf)
        return utf8Error(Utf8ErrorKind.unexpectedContinuation, byteOffset);
    if (first < 0xc2 || first > 0xf4)
        return utf8Error(Utf8ErrorKind.invalidLeadingByte, byteOffset);

    const width = first <= 0xdf ? 2u : first <= 0xef ? 3u : 4u;
    u8[4] bytes;
    bytes[0] = first;
    foreach (index; 1 .. width)
    {
        const currentOffset = byteOffset + index;
        if (currentOffset >= candidate.length)
            return utf8Error(Utf8ErrorKind.truncatedSequence, candidate.length);
        bytes[index] = cast(u8) candidate[currentOffset];
        if (!isContinuation(bytes[index]))
            return utf8Error(Utf8ErrorKind.invalidContinuation, currentOffset);
    }

    if (first == 0xe0 && bytes[1] < 0xa0)
        return utf8Error(Utf8ErrorKind.overlongEncoding, byteOffset);
    if (first == 0xed && bytes[1] > 0x9f)
        return utf8Error(Utf8ErrorKind.surrogateCodePoint, byteOffset);
    if (first == 0xf0 && bytes[1] < 0x90)
        return utf8Error(Utf8ErrorKind.overlongEncoding, byteOffset);
    if (first == 0xf4 && bytes[1] > 0x8f)
        return utf8Error(Utf8ErrorKind.codePointOutOfRange, byteOffset);

    uint scalar;
    if (width == 2)
        scalar = first & 0x1f;
    else if (width == 3)
        scalar = first & 0x0f;
    else
        scalar = first & 0x07;
    foreach (index; 1 .. width)
        scalar = (scalar << 6) | (bytes[index] & 0x3f);

    *output = DecodedCodePoint(cast(dchar) scalar, byteOffset, cast(u8) width);
    return Utf8Error.init;
}

Utf8Error decodePreviousCodePoint(
    scope String candidate,
    size_t endByteOffset,
    scope DecodedCodePoint* output,
) @safe
{
    version (XTB_Checked)
        require(output !is null, "decoded code point output is null");
    *output = DecodedCodePoint.init;
    version (XTB_Checked)
        require(endByteOffset > 0 && endByteOffset <= candidate.length,
            "UTF-8 end byte offset out of bounds");

    size_t beginByteOffset = endByteOffset - 1;
    size_t continuationCount;
    while (beginByteOffset != 0 &&
        isContinuation(cast(u8) candidate[beginByteOffset]) &&
        continuationCount < 3)
    {
        --beginByteOffset;
        ++continuationCount;
    }

    DecodedCodePoint decoded;
    const error = decodeCodePoint(candidate, beginByteOffset, &decoded);
    if (error.failed)
        return error;
    const decodedEnd = decoded.byteOffset + decoded.byteLength;
    if (decodedEnd != endByteOffset)
        return utf8Error(Utf8ErrorKind.unexpectedContinuation, decodedEnd);
    *output = decoded;
    return Utf8Error.init;
}

Utf8Error validateUtf8(scope String candidate) @safe
{
    size_t byteOffset;
    while (byteOffset < candidate.length)
    {
        DecodedCodePoint decoded;
        const error = decodeCodePoint(candidate, byteOffset, &decoded);
        if (error.failed)
            return error;
        byteOffset += decoded.byteLength;
    }
    return Utf8Error.init;
}

Utf8Error validateUtf8(scope const(u8)[] candidate) @trusted
{
    return validateUtf8(cast(String) candidate);
}

bool isValidUtf8(scope String candidate) @safe
{
    return validateUtf8(candidate).succeeded;
}

bool isValidUtf8(scope const(u8)[] candidate) @trusted
{
    return validateUtf8(candidate).succeeded;
}

Utf8StringResult asString(return scope const(u8)[] bytes) @trusted
{
    const error = validateUtf8(bytes);
    return error.failed
        ? Utf8StringResult(String.init, error) : Utf8StringResult(cast(String) bytes, Utf8Error.init);
}

bool isCodePointBoundary(scope String value, size_t byteOffset)
pure @safe
{
    if (byteOffset > value.length)
        return false;
    return byteOffset == 0 || byteOffset == value.length ||
        !isContinuation(cast(u8) value[byteOffset]);
}

size_t floorCodePointBoundary(scope String value, size_t byteOffset)
pure @safe
{
    if (byteOffset > value.length)
        byteOffset = value.length;
    while (byteOffset != 0 && byteOffset < value.length &&
        isContinuation(cast(u8) value[byteOffset]))
        --byteOffset;
    return byteOffset;
}

size_t ceilCodePointBoundary(scope String value, size_t byteOffset)
pure @safe
{
    if (byteOffset > value.length)
        byteOffset = value.length;
    while (byteOffset < value.length &&
        isContinuation(cast(u8) value[byteOffset]))
        ++byteOffset;
    return byteOffset;
}

bool isUnicodeScalar(dchar value) pure @safe
{
    return value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff);
}

bool tryEncodeUtf8(dchar value, scope EncodedCodePoint* output) @safe
{
    version (XTB_Checked)
        require(output !is null, "encoded code point output is null");
    *output = EncodedCodePoint.init;
    if (!isUnicodeScalar(value))
        return false;

    if (value <= 0x7f)
    {
        output.bytes_[0] = cast(char) value;
        output.byteLength_ = 1;
    }
    else if (value <= 0x7ff)
    {
        output.bytes_[0] = cast(char)(0xc0 | (value >> 6));
        output.bytes_[1] = cast(char)(0x80 | (value & 0x3f));
        output.byteLength_ = 2;
    }
    else if (value <= 0xffff)
    {
        output.bytes_[0] = cast(char)(0xe0 | (value >> 12));
        output.bytes_[1] = cast(char)(0x80 | ((value >> 6) & 0x3f));
        output.bytes_[2] = cast(char)(0x80 | (value & 0x3f));
        output.byteLength_ = 3;
    }
    else
    {
        output.bytes_[0] = cast(char)(0xf0 | (value >> 18));
        output.bytes_[1] = cast(char)(0x80 | ((value >> 12) & 0x3f));
        output.bytes_[2] = cast(char)(0x80 | ((value >> 6) & 0x3f));
        output.bytes_[3] = cast(char)(0x80 | (value & 0x3f));
        output.byteLength_ = 4;
    }
    return true;
}

EncodedCodePoint encodeUtf8(dchar value) @safe
{
    EncodedCodePoint result;
    const succeeded = tryEncodeUtf8(value, &result);
    version (XTB_Checked)
        require(succeeded, "invalid Unicode scalar value");
    return result;
}

u8 encodedUtf8Length(dchar value) @safe
{
    version (XTB_Checked)
        require(isUnicodeScalar(value), "invalid Unicode scalar value");
    return value <= 0x7f ? 1 : value <= 0x7ff ? 2 : value <= 0xffff ? 3 : 4;
}

size_t codePointCount(scope String value) @safe
{
    size_t result;
    size_t byteOffset;
    while (byteOffset < value.length)
    {
        DecodedCodePoint decoded;
        const status = decodeCodePoint(value, byteOffset, &decoded);
        version (XTB_Checked)
            require(status.succeeded, "invalid UTF-8 String");
        byteOffset += decoded.byteLength;
        ++result;
    }
    return result;
}

struct CodePointRange
{
nothrow @nogc:

    private String remaining_;

    bool empty() const pure @safe
    {
        return remaining_.length == 0;
    }

    dchar front() const @safe
    {
        version (XTB_Checked)
            require(!empty, "front of empty code point range");
        DecodedCodePoint decoded;
        const status = decodeCodePoint(remaining_, 0, &decoded);
        version (XTB_Checked)
            require(status.succeeded, "invalid UTF-8 String");
        return decoded.value;
    }

    dchar back() const @safe
    {
        version (XTB_Checked)
            require(!empty, "back of empty code point range");
        DecodedCodePoint decoded;
        const status = decodePreviousCodePoint(
            remaining_,
            remaining_.length,
            &decoded,
        );
        version (XTB_Checked)
            require(status.succeeded, "invalid UTF-8 String");
        return decoded.value;
    }

    void popFront() @safe
    {
        version (XTB_Checked)
            require(!empty, "popFront of empty code point range");
        DecodedCodePoint decoded;
        const status = decodeCodePoint(remaining_, 0, &decoded);
        version (XTB_Checked)
            require(status.succeeded, "invalid UTF-8 String");
        remaining_ = remaining_[decoded.byteLength .. $];
    }

    void popBack() @safe
    {
        version (XTB_Checked)
            require(!empty, "popBack of empty code point range");
        DecodedCodePoint decoded;
        const status = decodePreviousCodePoint(
            remaining_,
            remaining_.length,
            &decoded,
        );
        version (XTB_Checked)
            require(status.succeeded, "invalid UTF-8 String");
        remaining_ = remaining_[0 .. decoded.byteOffset];
    }

    CodePointRange save() const return scope pure @safe
    {
        return this;
    }

    int opApply(
        scope int delegate(dchar) nothrow @nogc @safe callback,
    ) const @safe
    {
        version (XTB_Checked)
            require(callback !is null, "code point iteration callback is null");
        CodePointRange range;
        range.remaining_ = remaining_;
        while (!range.empty)
        {
            const control = callback(range.front);
            if (control != 0)
                return control;
            range.popFront();
        }
        return 0;
    }

    int opApply(
        scope int delegate(dchar) nothrow @nogc @system callback,
    ) const
    @system
    {
        version (XTB_Checked)
            require(callback !is null, "code point iteration callback is null");
        CodePointRange range;
        range.remaining_ = remaining_;
        while (!range.empty)
        {
            const control = callback(range.front);
            if (control != 0)
                return control;
            range.popFront();
        }
        return 0;
    }
}

CodePointRange codePoints(return scope String value) pure @safe
{
    CodePointRange result;
    result.remaining_ = value;
    return result;
}

struct CodePointOffsetRange
{
nothrow @nogc:

    private String original_;
    private size_t beginByteOffset_;
    private size_t endByteOffset_;

    bool empty() const pure @safe
    {
        return beginByteOffset_ == endByteOffset_;
    }

    DecodedCodePoint front() const @safe
    {
        version (XTB_Checked)
            require(!empty, "front of empty code point offset range");
        DecodedCodePoint decoded;
        const status = decodeCodePoint(original_, beginByteOffset_, &decoded);
        version (XTB_Checked)
            require(status.succeeded, "invalid UTF-8 String");
        return decoded;
    }

    DecodedCodePoint back() const @safe
    {
        version (XTB_Checked)
            require(!empty, "back of empty code point offset range");
        DecodedCodePoint decoded;
        const status = decodePreviousCodePoint(
            original_,
            endByteOffset_,
            &decoded,
        );
        version (XTB_Checked)
            require(status.succeeded, "invalid UTF-8 String");
        return decoded;
    }

    void popFront() @safe
    {
        const decoded = front;
        beginByteOffset_ += decoded.byteLength;
    }

    void popBack() @safe
    {
        const decoded = back;
        endByteOffset_ = decoded.byteOffset;
    }

    CodePointOffsetRange save() const return scope pure @safe
    {
        return this;
    }

    int opApply(
        scope int delegate(DecodedCodePoint) nothrow @nogc @safe callback,
    ) const @safe
    {
        version (XTB_Checked)
            require(callback !is null,
                "code point offset iteration callback is null");
        CodePointOffsetRange range;
        range.original_ = original_;
        range.beginByteOffset_ = beginByteOffset_;
        range.endByteOffset_ = endByteOffset_;
        while (!range.empty)
        {
            const control = callback(range.front);
            if (control != 0)
                return control;
            range.popFront();
        }
        return 0;
    }

    int opApply(
        scope int delegate(DecodedCodePoint) nothrow @nogc @system callback,
    ) const
    @system
    {
        version (XTB_Checked)
            require(callback !is null,
                "code point offset iteration callback is null");
        CodePointOffsetRange range;
        range.original_ = original_;
        range.beginByteOffset_ = beginByteOffset_;
        range.endByteOffset_ = endByteOffset_;
        while (!range.empty)
        {
            const control = callback(range.front);
            if (control != 0)
                return control;
            range.popFront();
        }
        return 0;
    }
}

CodePointOffsetRange codePointsWithOffsets(return scope String value)
pure @safe
{
    CodePointOffsetRange result;
    result.original_ = value;
    result.endByteOffset_ = value.length;
    return result;
}

version (unittest) enum utf8TestBody = q{
    assert(validateUtf8(String.init).succeeded);
        assert(validateUtf8("ASCII\0text").succeeded);
        assert(validateUtf8("Aé🙂").succeeded);
        assert("Aé🙂".codePointCount == 3);

        u8[1] leadingByte;
        foreach (uint candidate; 0 .. 256)
        {
            leadingByte[0] = cast(u8) candidate;
            DecodedCodePoint decoded;
            const error = decodeCodePoint(
                cast(String) leadingByte[],
                0,
                &decoded,
            );
            if (candidate <= 0x7f)
                assert(error.succeeded && decoded.value == candidate);
            else if (candidate <= 0xbf)
                assert(error.kind == Utf8ErrorKind.unexpectedContinuation);
            else if (candidate <= 0xc1 || candidate >= 0xf5)
                assert(error.kind == Utf8ErrorKind.invalidLeadingByte);
            else
                assert(error.kind == Utf8ErrorKind.truncatedSequence &&
                    error.byteOffset == 1);
        }

        const u8[4] validFour = [0xf1, 0x80, 0x80, 0x80];
        foreach (length; 1 .. validFour.length)
            assertUtf8Error(
                validFour[0 .. length],
                Utf8ErrorKind.truncatedSequence,
                length,
            );
        foreach (continuation; 1 .. validFour.length)
        {
            u8[4] invalidFour = validFour;
            invalidFour[continuation] = 0x20;
            assertUtf8Error(
                invalidFour[],
                Utf8ErrorKind.invalidContinuation,
                continuation,
            );
        }

        assertUtf8Error([0x80], Utf8ErrorKind.unexpectedContinuation, 0);
        assertUtf8Error([0xbf], Utf8ErrorKind.unexpectedContinuation, 0);
        assertUtf8Error([0xc0, 0x80], Utf8ErrorKind.invalidLeadingByte, 0);
        assertUtf8Error([0xc1, 0xbf], Utf8ErrorKind.invalidLeadingByte, 0);
        assertUtf8Error([0xf5, 0x80, 0x80, 0x80], Utf8ErrorKind.invalidLeadingByte, 0);
        assertUtf8Error([0xff], Utf8ErrorKind.invalidLeadingByte, 0);
        assertUtf8Error([0xc2], Utf8ErrorKind.truncatedSequence, 1);
        assertUtf8Error([0xe1, 0x80], Utf8ErrorKind.truncatedSequence, 2);
        assertUtf8Error([0xf1, 0x80, 0x80], Utf8ErrorKind.truncatedSequence, 3);
        assertUtf8Error([0xc2, 0x20], Utf8ErrorKind.invalidContinuation, 1);
        assertUtf8Error([0xe1, 0x80, 0x20], Utf8ErrorKind.invalidContinuation, 2);
        assertUtf8Error([0xf1, 0x80, 0x80, 0x20], Utf8ErrorKind.invalidContinuation, 3);
        assertUtf8Error([0xe0, 0x9f, 0xbf], Utf8ErrorKind.overlongEncoding, 0);
        assertUtf8Error([0xf0, 0x8f, 0xbf, 0xbf], Utf8ErrorKind.overlongEncoding, 0);
        assertUtf8Error([0xed, 0xa0, 0x80], Utf8ErrorKind.surrogateCodePoint, 0);
        assertUtf8Error([0xf4, 0x90, 0x80, 0x80], Utf8ErrorKind.codePointOutOfRange, 0);
        assertUtf8Error(['o', 'k', 0xc2], Utf8ErrorKind.truncatedSequence, 3);

        const checked = (cast(const(u8)[]) "Aé🙂").asString;
        assert(checked.succeeded);
        assert(checked.value.ptr is "Aé🙂".ptr);
        assert(checked.value.length == "Aé🙂".length);
        const u8[1] invalidBytes = [0xff];
        const rejected = invalidBytes[].asString;
        assert(rejected.failed && rejected.value.length == 0);

        String mixed = "Aé🙂";
        assert(mixed.isCodePointBoundary(0));
        assert(mixed.isCodePointBoundary(1));
        assert(!mixed.isCodePointBoundary(2));
        assert(mixed.isCodePointBoundary(3));
        assert(!mixed.isCodePointBoundary(4));
        assert(!mixed.isCodePointBoundary(5));
        assert(!mixed.isCodePointBoundary(6));
        assert(mixed.isCodePointBoundary(7));
        assert(!mixed.isCodePointBoundary(8));
        assert(mixed.floorCodePointBoundary(6) == 3);
        assert(mixed.ceilCodePointBoundary(4) == 7);
        assert(mixed.floorCodePointBoundary(99) == 7);
        assert(mixed.ceilCodePointBoundary(99) == 7);

        String widths = "¢€🙂";
        const size_t[4] boundaries = [0, 2, 5, 9];
        foreach (byteOffset; 0 .. widths.length + 1)
        {
            bool expectedBoundary;
            foreach (boundary; boundaries)
                expectedBoundary = expectedBoundary || byteOffset == boundary;
            assert(widths.isCodePointBoundary(byteOffset) == expectedBoundary);
        }
        const size_t[10] floors = [0, 0, 2, 2, 2, 5, 5, 5, 5, 9];
        const size_t[10] ceilings = [0, 2, 2, 5, 5, 5, 9, 9, 9, 9];
        foreach (byteOffset; 0 .. floors.length)
        {
            assert(widths.floorCodePointBoundary(byteOffset) == floors[byteOffset]);
            assert(widths.ceilCodePointBoundary(byteOffset) == ceilings[byteOffset]);
        }

        dchar[3] forward;
        size_t forwardCount;
        foreach (codePoint; mixed.codePoints)
            forward[forwardCount++] = codePoint;
        assert(forwardCount == 3);
        assert(forward == [cast(dchar) 'A', cast(dchar) 0xe9, cast(dchar) 0x1f642]);

        size_t earlyCount;
        foreach (codePoint; mixed.codePoints)
        {
            ++earlyCount;
            break;
        }
        assert(earlyCount == 1);

        auto originalRange = mixed.codePoints;
        auto copiedRange = originalRange.save;
        originalRange.popFront();
        assert(originalRange.front == 0xe9);
        assert(copiedRange.front == 'A');

        auto reverse = mixed.codePoints;
        assert(reverse.back == 0x1f642);
        reverse.popBack();
        assert(reverse.back == 0xe9);
        reverse.popBack();
        assert(reverse.back == 'A');
        reverse.popBack();
        assert(reverse.empty);

        auto offsets = mixed.codePointsWithOffsets;
        assert(offsets.front == DecodedCodePoint('A', 0, 1));
        offsets.popFront();
        assert(offsets.front == DecodedCodePoint(0xe9, 1, 2));
        assert(offsets.back == DecodedCodePoint(0x1f642, 3, 4));
        offsets.popBack();
        assert(offsets.back == DecodedCodePoint(0xe9, 1, 2));

        foreach (uint scalar; 0 .. 0x110000)
        {
            const value = cast(dchar) scalar;
            if (!isUnicodeScalar(value))
                continue;
            EncodedCodePoint encoded;
            assert(tryEncodeUtf8(value, &encoded));
            assert(encoded.byteLength == encodedUtf8Length(value));
            DecodedCodePoint decoded;
            const codeUnits = encoded.codeUnits;
            assert(decodeCodePoint(codeUnits[0 .. encoded.byteLength], 0, &decoded).succeeded);
            assert(decoded.value == value);
            assert(decoded.byteLength == encoded.byteLength);
        }

        EncodedCodePoint invalid = encodeUtf8('x');
        assert(!tryEncodeUtf8(cast(dchar) 0xd800, &invalid));
        assert(invalid.byteLength == 0);
        assert(!tryEncodeUtf8(cast(dchar) 0x110000, &invalid));
        assert(invalid.byteLength == 0);
};
