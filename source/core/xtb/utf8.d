module xtb.utf8;

nothrow @nogc:

import xtb.panic;
import xtb.types;

enum Utf8ErrorKind : u8
{
    none,
    unexpected_continuation,
    invalid_leading_byte,
    truncated_sequence,
    invalid_continuation,
    overlong_encoding,
    surrogate_code_point,
    code_point_out_of_range,
}

struct Utf8Error
{
nothrow @nogc:

    Utf8ErrorKind kind;
    usize byte_offset;

    bool succeeded() const pure @safe
    {
        return this.kind == Utf8ErrorKind.none;
    }

    bool failed() const pure @safe
    {
        return !this.succeeded;
    }
}

struct Utf8StringResult
{
nothrow @nogc:

    String value;
    Utf8Error error;

    bool succeeded() const pure @safe
    {
        return this.error.succeeded;
    }

    bool failed() const pure @safe
    {
        return this.error.failed;
    }
}

struct DecodedCodePoint
{
    dchar value;
    usize byte_offset;
    u8 byte_length;
}

/// UTF-8 code units for one Unicode scalar value.
/// `byte_length` identifies the initialized prefix of `bytes`.
/// Callers that mutate either field must preserve a valid scalar encoding.
struct EncodedCodePoint
{
nothrow @nogc:

    char[4] bytes;
    u8 byte_length;
}

private Utf8Error utf8_error(
    Utf8ErrorKind kind,
    usize byte_offset,
) pure @safe
{
    return Utf8Error(kind, byte_offset);
}

private bool is_continuation(u8 value) pure @safe
{
    return (value & 0xc0) == 0x80;
}

/// Decodes the code point beginning at `byte_offset`.
/// `output` is required, and `byte_offset` must index `candidate`.
Utf8Error decode_code_point(
    scope String candidate,
    usize byte_offset,
    scope DecodedCodePoint* output,
) @safe
{
    require(output !is null, "decoded code point output must not be null");
    *output = DecodedCodePoint.init;
    require(
        byte_offset < candidate.length,
        "UTF-8 byte offset is out of bounds",
    );

    const first = cast(u8) candidate[byte_offset];
    if (first <= 0x7f)
    {
        *output = DecodedCodePoint(cast(dchar) first, byte_offset, 1);
        return Utf8Error.init;
    }
    if (first >= 0x80 && first <= 0xbf)
    {
        return utf8_error(Utf8ErrorKind.unexpected_continuation, byte_offset);
    }
    if (first < 0xc2 || first > 0xf4)
    {
        return utf8_error(Utf8ErrorKind.invalid_leading_byte, byte_offset);
    }

    const u8 width = first <= 0xdf ? 2 : first <= 0xef ? 3 : 4;
    u8[4] bytes;
    bytes[0] = first;
    foreach (index; 1 .. width)
    {
        const current_offset = byte_offset + index;
        if (current_offset >= candidate.length)
        {
            return utf8_error(Utf8ErrorKind.truncated_sequence, candidate.length);
        }
        bytes[index] = cast(u8) candidate[current_offset];
        if (!is_continuation(bytes[index]))
        {
            return utf8_error(Utf8ErrorKind.invalid_continuation, current_offset);
        }
    }

    if (first == 0xe0 && bytes[1] < 0xa0)
    {
        return utf8_error(Utf8ErrorKind.overlong_encoding, byte_offset);
    }
    if (first == 0xed && bytes[1] > 0x9f)
    {
        return utf8_error(Utf8ErrorKind.surrogate_code_point, byte_offset);
    }
    if (first == 0xf0 && bytes[1] < 0x90)
    {
        return utf8_error(Utf8ErrorKind.overlong_encoding, byte_offset);
    }
    if (first == 0xf4 && bytes[1] > 0x8f)
    {
        return utf8_error(Utf8ErrorKind.code_point_out_of_range, byte_offset);
    }

    u32 scalar;
    if (width == 2)
    {
        scalar = first & 0x1f;
    }
    else if (width == 3)
    {
        scalar = first & 0x0f;
    }
    else
    {
        scalar = first & 0x07;
    }
    foreach (index; 1 .. width)
    {
        scalar = (scalar << 6) | (bytes[index] & 0x3f);
    }

    *output = DecodedCodePoint(cast(dchar) scalar, byte_offset, width);
    return Utf8Error.init;
}

/// Decodes the code point ending at `end_byte_offset`.
/// `output` is required; the offset must be within `candidate` and nonzero.
Utf8Error decode_previous_code_point(
    scope String candidate,
    usize end_byte_offset,
    scope DecodedCodePoint* output,
) @safe
{
    require(output !is null, "decoded code point output must not be null");
    *output = DecodedCodePoint.init;
    require(
        end_byte_offset > 0 && end_byte_offset <= candidate.length,
        "UTF-8 end byte offset is out of bounds",
    );

    usize begin_byte_offset = end_byte_offset - 1;
    usize continuation_count;
    while (
        begin_byte_offset != 0
        && is_continuation(cast(u8) candidate[begin_byte_offset])
        && continuation_count < 3
    )
    {
        --begin_byte_offset;
        ++continuation_count;
    }

    DecodedCodePoint decoded;
    const error = decode_code_point(candidate, begin_byte_offset, &decoded);
    if (error.failed) return error;

    const decoded_end = decoded.byte_offset + decoded.byte_length;
    if (decoded_end != end_byte_offset)
    {
        return utf8_error(Utf8ErrorKind.unexpected_continuation, decoded_end);
    }
    *output = decoded;
    return Utf8Error.init;
}

Utf8Error validate_utf8(scope String candidate) @safe
{
    usize byte_offset;
    while (byte_offset < candidate.length)
    {
        DecodedCodePoint decoded;
        const error = decode_code_point(candidate, byte_offset, &decoded);
        if (error.failed) return error;

        byte_offset += decoded.byte_length;
    }
    return Utf8Error.init;
}

Utf8Error validate_utf8(scope const(u8)[] candidate) @trusted
{
    // char and u8 have identical representation; const preserves immutability,
    // and the casted view does not escape this call.
    return validate_utf8(cast(String) candidate);
}

bool is_valid_utf8(scope String candidate) @safe
{
    return validate_utf8(candidate).succeeded;
}

bool is_valid_utf8(scope const(u8)[] candidate) @safe
{
    return validate_utf8(candidate).succeeded;
}

/// Validates `bytes` and returns a borrowed string view on success.
/// The returned view is valid for the lifetime of `bytes`.
Utf8StringResult as_string(return scope const(u8)[] bytes) @trusted
{
    const error = validate_utf8(bytes);
    if (error.failed) return Utf8StringResult(String.init, error);

    // char and u8 have identical representation; const and return scope
    // preserve immutability and prevent the borrowed view from outliving bytes.
    return Utf8StringResult(cast(String) bytes, Utf8Error.init);
}

bool is_code_point_boundary(
    scope String value,
    usize byte_offset,
) pure @safe
{
    if (byte_offset > value.length) return false;

    return byte_offset == 0
        || byte_offset == value.length
        || !is_continuation(cast(u8) value[byte_offset]);
}

usize floor_code_point_boundary(
    scope String value,
    usize byte_offset,
) pure @safe
{
    if (byte_offset > value.length) byte_offset = value.length;

    while (
        byte_offset != 0
        && byte_offset < value.length
        && is_continuation(cast(u8) value[byte_offset])
    )
    {
        --byte_offset;
    }
    return byte_offset;
}

usize ceil_code_point_boundary(
    scope String value,
    usize byte_offset,
) pure @safe
{
    if (byte_offset > value.length) byte_offset = value.length;

    while (
        byte_offset < value.length
        && is_continuation(cast(u8) value[byte_offset])
    )
    {
        ++byte_offset;
    }
    return byte_offset;
}

bool is_unicode_scalar(dchar value) pure @safe
{
    return value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff);
}

/// Encodes `value` when it is a Unicode scalar. `output` is required.
bool try_encode_utf8(dchar value, scope EncodedCodePoint* output) @safe
{
    require(output !is null, "encoded code point output must not be null");
    *output = EncodedCodePoint.init;
    if (!is_unicode_scalar(value)) return false;

    if (value <= 0x7f)
    {
        output.bytes[0] = cast(char) value;
        output.byte_length = 1;
    }
    else if (value <= 0x7ff)
    {
        output.bytes[0] = cast(char)(0xc0 | (value >> 6));
        output.bytes[1] = cast(char)(0x80 | (value & 0x3f));
        output.byte_length = 2;
    }
    else if (value <= 0xffff)
    {
        output.bytes[0] = cast(char)(0xe0 | (value >> 12));
        output.bytes[1] = cast(char)(0x80 | ((value >> 6) & 0x3f));
        output.bytes[2] = cast(char)(0x80 | (value & 0x3f));
        output.byte_length = 3;
    }
    else
    {
        output.bytes[0] = cast(char)(0xf0 | (value >> 18));
        output.bytes[1] = cast(char)(0x80 | ((value >> 12) & 0x3f));
        output.bytes[2] = cast(char)(0x80 | ((value >> 6) & 0x3f));
        output.bytes[3] = cast(char)(0x80 | (value & 0x3f));
        output.byte_length = 4;
    }
    return true;
}

/// Encodes `value`, which must be a Unicode scalar.
EncodedCodePoint encode_utf8(dchar value) @safe
{
    EncodedCodePoint result;
    const succeeded = try_encode_utf8(value, &result);
    require(succeeded, "invalid Unicode scalar value");
    return result;
}

/// Returns the encoded width of `value`, which must be a Unicode scalar.
u8 encoded_utf8_length(dchar value) @safe
{
    require(is_unicode_scalar(value), "invalid Unicode scalar value");

    if (value <= 0x7f) return 1;
    if (value <= 0x7ff) return 2;
    if (value <= 0xffff) return 3;

    return 4;
}

/// Counts code points in `value`, which must contain valid UTF-8.
usize code_point_count(scope String value) @safe
{
    usize result;
    usize byte_offset;
    while (byte_offset < value.length)
    {
        DecodedCodePoint decoded;
        const status = decode_code_point(value, byte_offset, &decoded);
        require(status.succeeded, "string contains invalid UTF-8");
        byte_offset += decoded.byte_length;
        ++result;
    }
    return result;
}

/// A borrowed bidirectional range over the code points in a valid UTF-8 string.
/// Callers that mutate `remaining` must preserve that validity and boundaries.
struct CodePointRange
{
nothrow @nogc:

    String remaining;

    bool empty() const pure @safe
    {
        return this.remaining.length == 0;
    }

    dchar front() const @safe
    {
        require(
            !this.empty,
            "cannot access the front of an empty code point range",
        );

        DecodedCodePoint decoded;
        const status = decode_code_point(this.remaining, 0, &decoded);
        require(status.succeeded, "string contains invalid UTF-8");
        return decoded.value;
    }

    dchar back() const @safe
    {
        require(
            !this.empty,
            "cannot access the back of an empty code point range",
        );

        DecodedCodePoint decoded;
        const status = decode_previous_code_point(
            this.remaining,
            this.remaining.length,
            &decoded,
        );
        require(status.succeeded, "string contains invalid UTF-8");
        return decoded.value;
    }

    void pop_front() @safe
    {
        require(
            !this.empty,
            "cannot pop the front of an empty code point range",
        );

        DecodedCodePoint decoded;
        const status = decode_code_point(this.remaining, 0, &decoded);
        require(status.succeeded, "string contains invalid UTF-8");
        this.remaining = this.remaining[decoded.byte_length .. $];
    }

    void pop_back() @safe
    {
        require(
            !this.empty,
            "cannot pop the back of an empty code point range",
        );

        DecodedCodePoint decoded;
        const status = decode_previous_code_point(
            this.remaining,
            this.remaining.length,
            &decoded,
        );
        require(status.succeeded, "string contains invalid UTF-8");
        this.remaining = this.remaining[0 .. decoded.byte_offset];
    }

    CodePointRange save() const return scope pure @safe
    {
        return this;
    }

    i32 opApply(
        scope i32 delegate(dchar) nothrow @nogc @safe callback,
    ) const @safe
    {
        require(
            callback !is null,
            "code point iteration callback must not be null",
        );

        CodePointRange range = this;
        while (!range.empty)
        {
            const control = callback(range.front);
            if (control != 0) return control;

            range.pop_front();
        }
        return 0;
    }

    i32 opApply(
        scope i32 delegate(dchar) nothrow @nogc @system callback,
    ) const @system
    {
        require(
            callback !is null,
            "code point iteration callback must not be null",
        );

        CodePointRange range = this;
        while (!range.empty)
        {
            const control = callback(range.front);
            if (control != 0) return control;

            range.pop_front();
        }
        return 0;
    }
}

/// Returns a borrowed range over `value`, which must contain valid UTF-8.
CodePointRange code_points(return scope String value) pure @safe
{
    return CodePointRange(remaining: value);
}

/// A borrowed bidirectional range that preserves each code point's byte offset.
/// `original` must remain valid UTF-8. The offsets must remain ordered within
/// `original` and positioned at code point boundaries.
struct CodePointOffsetRange
{
nothrow @nogc:

    String original;
    usize begin_byte_offset;
    usize end_byte_offset;

    bool empty() const pure @safe
    {
        return this.begin_byte_offset == this.end_byte_offset;
    }

    DecodedCodePoint front() const @safe
    {
        require(
            !this.empty,
            "cannot access the front of an empty code point offset range",
        );

        DecodedCodePoint decoded;
        const status = decode_code_point(
            this.original,
            this.begin_byte_offset,
            &decoded,
        );
        require(status.succeeded, "string contains invalid UTF-8");
        return decoded;
    }

    DecodedCodePoint back() const @safe
    {
        require(
            !this.empty,
            "cannot access the back of an empty code point offset range",
        );

        DecodedCodePoint decoded;
        const status = decode_previous_code_point(
            this.original,
            this.end_byte_offset,
            &decoded,
        );
        require(status.succeeded, "string contains invalid UTF-8");
        return decoded;
    }

    void pop_front() @safe
    {
        const decoded = this.front;
        this.begin_byte_offset += decoded.byte_length;
    }

    void pop_back() @safe
    {
        const decoded = this.back;
        this.end_byte_offset = decoded.byte_offset;
    }

    CodePointOffsetRange save() const return scope pure @safe
    {
        return this;
    }

    i32 opApply(
        scope i32 delegate(DecodedCodePoint) nothrow @nogc @safe callback,
    ) const @safe
    {
        require(
            callback !is null,
            "code point offset iteration callback must not be null",
        );

        CodePointOffsetRange range = this;
        while (!range.empty)
        {
            const control = callback(range.front);
            if (control != 0) return control;

            range.pop_front();
        }
        return 0;
    }

    i32 opApply(
        scope i32 delegate(DecodedCodePoint) nothrow @nogc @system callback,
    ) const @system
    {
        require(
            callback !is null,
            "code point offset iteration callback must not be null",
        );

        CodePointOffsetRange range = this;
        while (!range.empty)
        {
            const control = callback(range.front);
            if (control != 0) return control;

            range.pop_front();
        }
        return 0;
    }
}

/// Returns a borrowed offset range over `value`, which must contain valid UTF-8.
CodePointOffsetRange code_points_with_offsets(
    return scope String value,
) pure @safe
{
    return CodePointOffsetRange(
        original: value,
        begin_byte_offset: 0,
        end_byte_offset: value.length,
    );
}

version (unittest)
{
    enum utf8_test_body = q{
        assert(validate_utf8(String.init).succeeded);
        assert(validate_utf8("ASCII\0text").succeeded);
        assert(validate_utf8("Aé🙂").succeeded);
        assert("Aé🙂".code_point_count == 3);

        u8[1] leading_byte;
        foreach (u32 candidate; 0 .. 256)
        {
            leading_byte[0] = cast(u8) candidate;
            DecodedCodePoint decoded;
            const error = decode_code_point(
                cast(String) leading_byte[],
                0,
                &decoded,
            );
            if (candidate <= 0x7f)
            {
                assert(error.succeeded && decoded.value == candidate);
            }
            else if (candidate <= 0xbf)
            {
                assert(error.kind == Utf8ErrorKind.unexpected_continuation);
            }
            else if (candidate <= 0xc1 || candidate >= 0xf5)
            {
                assert(error.kind == Utf8ErrorKind.invalid_leading_byte);
            }
            else
            {
                assert(
                    error.kind == Utf8ErrorKind.truncated_sequence
                        && error.byte_offset == 1,
                );
            }
        }

        const u8[4] valid_four = [0xf1, 0x80, 0x80, 0x80];
        foreach (length; 1 .. valid_four.length)
        {
            assert_utf8_error(
                valid_four[0 .. length],
                Utf8ErrorKind.truncated_sequence,
                length,
            );
        }
        foreach (continuation; 1 .. valid_four.length)
        {
            u8[4] invalid_four = valid_four;
            invalid_four[continuation] = 0x20;
            assert_utf8_error(
                invalid_four[],
                Utf8ErrorKind.invalid_continuation,
                continuation,
            );
        }

        assert_utf8_error([0x80], Utf8ErrorKind.unexpected_continuation, 0);
        assert_utf8_error([0xbf], Utf8ErrorKind.unexpected_continuation, 0);
        assert_utf8_error([0xc0, 0x80], Utf8ErrorKind.invalid_leading_byte, 0);
        assert_utf8_error([0xc1, 0xbf], Utf8ErrorKind.invalid_leading_byte, 0);
        assert_utf8_error(
            [0xf5, 0x80, 0x80, 0x80],
            Utf8ErrorKind.invalid_leading_byte,
            0,
        );
        assert_utf8_error([0xff], Utf8ErrorKind.invalid_leading_byte, 0);
        assert_utf8_error([0xc2], Utf8ErrorKind.truncated_sequence, 1);
        assert_utf8_error([0xe1, 0x80], Utf8ErrorKind.truncated_sequence, 2);
        assert_utf8_error(
            [0xf1, 0x80, 0x80],
            Utf8ErrorKind.truncated_sequence,
            3,
        );
        assert_utf8_error([0xc2, 0x20], Utf8ErrorKind.invalid_continuation, 1);
        assert_utf8_error(
            [0xe1, 0x80, 0x20],
            Utf8ErrorKind.invalid_continuation,
            2,
        );
        assert_utf8_error(
            [0xf1, 0x80, 0x80, 0x20],
            Utf8ErrorKind.invalid_continuation,
            3,
        );
        assert_utf8_error(
            [0xe0, 0x9f, 0xbf],
            Utf8ErrorKind.overlong_encoding,
            0,
        );
        assert_utf8_error(
            [0xf0, 0x8f, 0xbf, 0xbf],
            Utf8ErrorKind.overlong_encoding,
            0,
        );
        assert_utf8_error(
            [0xed, 0xa0, 0x80],
            Utf8ErrorKind.surrogate_code_point,
            0,
        );
        assert_utf8_error(
            [0xf4, 0x90, 0x80, 0x80],
            Utf8ErrorKind.code_point_out_of_range,
            0,
        );
        assert_utf8_error(
            ['o', 'k', 0xc2],
            Utf8ErrorKind.truncated_sequence,
            3,
        );

        const checked = (cast(const(u8)[]) "Aé🙂").as_string;
        assert(checked.succeeded);
        assert(checked.value.ptr is "Aé🙂".ptr);
        assert(checked.value.length == "Aé🙂".length);
        const u8[1] invalid_bytes = [0xff];
        const rejected = invalid_bytes[].as_string;
        assert(rejected.failed && rejected.value.length == 0);

        String mixed = "Aé🙂";
        assert(mixed.is_code_point_boundary(0));
        assert(mixed.is_code_point_boundary(1));
        assert(!mixed.is_code_point_boundary(2));
        assert(mixed.is_code_point_boundary(3));
        assert(!mixed.is_code_point_boundary(4));
        assert(!mixed.is_code_point_boundary(5));
        assert(!mixed.is_code_point_boundary(6));
        assert(mixed.is_code_point_boundary(7));
        assert(!mixed.is_code_point_boundary(8));
        assert(mixed.floor_code_point_boundary(6) == 3);
        assert(mixed.ceil_code_point_boundary(4) == 7);
        assert(mixed.floor_code_point_boundary(99) == 7);
        assert(mixed.ceil_code_point_boundary(99) == 7);

        String widths = "¢€🙂";
        const usize[4] boundaries = [0, 2, 5, 9];
        foreach (byte_offset; 0 .. widths.length + 1)
        {
            bool expected_boundary;
            foreach (boundary; boundaries)
            {
                expected_boundary = expected_boundary || byte_offset == boundary;
            }
            assert(
                widths.is_code_point_boundary(byte_offset) == expected_boundary,
            );
        }
        const usize[10] floors = [0, 0, 2, 2, 2, 5, 5, 5, 5, 9];
        const usize[10] ceilings = [0, 2, 2, 5, 5, 5, 9, 9, 9, 9];
        foreach (byte_offset; 0 .. floors.length)
        {
            assert(
                widths.floor_code_point_boundary(byte_offset) == floors[byte_offset],
            );
            assert(
                widths.ceil_code_point_boundary(byte_offset) == ceilings[byte_offset],
            );
        }

        dchar[3] forward;
        usize forward_count;
        foreach (code_point; mixed.code_points)
        {
            forward[forward_count++] = code_point;
        }
        assert(forward_count == 3);
        assert(
            forward == [cast(dchar) 'A', cast(dchar) 0xe9, cast(dchar) 0x1f642],
        );

        usize early_count;
        foreach (code_point; mixed.code_points)
        {
            ++early_count;
            break;
        }
        assert(early_count == 1);

        auto original_range = mixed.code_points;
        auto copied_range = original_range.save;
        original_range.pop_front();
        assert(original_range.front == 0xe9);
        assert(copied_range.front == 'A');

        auto reverse = mixed.code_points;
        assert(reverse.back == 0x1f642);
        reverse.pop_back();
        assert(reverse.back == 0xe9);
        reverse.pop_back();
        assert(reverse.back == 'A');
        reverse.pop_back();
        assert(reverse.empty);

        auto offsets = mixed.code_points_with_offsets;
        assert(offsets.front == DecodedCodePoint('A', 0, 1));
        offsets.pop_front();
        assert(offsets.front == DecodedCodePoint(0xe9, 1, 2));
        assert(offsets.back == DecodedCodePoint(0x1f642, 3, 4));
        offsets.pop_back();
        assert(offsets.back == DecodedCodePoint(0xe9, 1, 2));

        foreach (u32 scalar; 0 .. 0x110000)
        {
            const value = cast(dchar) scalar;
            if (!is_unicode_scalar(value)) continue;

            EncodedCodePoint encoded;
            assert(try_encode_utf8(value, &encoded));
            assert(encoded.byte_length == encoded_utf8_length(value));

            DecodedCodePoint decoded;
            const code_units = encoded.bytes;
            assert(
                decode_code_point(
                    code_units[0 .. encoded.byte_length],
                    0,
                    &decoded,
                ).succeeded,
            );
            assert(decoded.value == value);
            assert(decoded.byte_length == encoded.byte_length);
        }

        EncodedCodePoint invalid = encode_utf8('x');
        assert(!try_encode_utf8(cast(dchar) 0xd800, &invalid));
        assert(invalid.byte_length == 0);
        assert(!try_encode_utf8(cast(dchar) 0x110000, &invalid));
        assert(invalid.byte_length == 0);
    };
}
