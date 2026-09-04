module xtb.numeric;

nothrow @nogc:

import xtb.panic;
import xtb.types;

private enum usize bytes_per_kibibyte = 1_024;
private enum usize bytes_per_mebibyte = 1_024 * bytes_per_kibibyte;
private enum usize bytes_per_gibibyte = 1_024 * bytes_per_mebibyte;
private enum usize bytes_per_tebibyte = 1_024 * bytes_per_gibibyte;

T min(T)(T left, T right) pure @safe
{
    return left < right ? left : right;
}

T max(T)(T left, T right) pure @safe
{
    return left > right ? left : right;
}

/// Returns `value` restricted to the inclusive range [`lower`, `upper`].
/// `lower` must not exceed `upper`.
T clamp(T)(T value, T lower, T upper) @safe
{
    require(lower <= upper, "invalid clamp range");

    if (value < lower) return lower;
    if (value > upper) return upper;

    return value;
}

usize grow_geometric(usize current, usize required) pure @safe
{
    if (required <= current) return current;
    if (current == 0 || current > usize.max / 2) return required;

    const doubled = current * 2;
    return doubled > required ? doubled : required;
}

bool add_overflows(usize left, usize right) pure @safe
{
    return right > usize.max - left;
}

bool multiply_overflows(usize left, usize right) pure @safe
{
    return left != 0 && right > usize.max / left;
}

private bool try_scale(
    usize count,
    usize multiplier,
    scope usize* output,
) pure @safe
{
    if (output is null) return false;

    *output = 0;
    if (multiply_overflows(count, multiplier)) return false;

    *output = count * multiplier;
    return true;
}

private usize scale(usize count, usize multiplier) @safe
{
    usize result;
    const succeeded = try_scale(count, multiplier, &result);
    require(succeeded, "byte count overflow");
    return result;
}

/// Converts kibibytes to bytes. The result must fit in `usize`.
usize kibibytes(usize count) @safe
{
    return scale(count, bytes_per_kibibyte);
}

/// Converts mebibytes to bytes. The result must fit in `usize`.
usize mebibytes(usize count) @safe
{
    return scale(count, bytes_per_mebibyte);
}

/// Converts gibibytes to bytes. The result must fit in `usize`.
usize gibibytes(usize count) @safe
{
    return scale(count, bytes_per_gibibyte);
}

/// Converts tebibytes to bytes. The result must fit in `usize`.
usize tebibytes(usize count) @safe
{
    return scale(count, bytes_per_tebibyte);
}

/// Attempts to convert kibibytes to bytes.
/// Returns `false` for overflow or a null `output`; writes zero on overflow.
bool try_kibibytes(usize count, scope usize* output) pure @safe
{
    return try_scale(count, bytes_per_kibibyte, output);
}

/// Attempts to convert mebibytes to bytes.
/// Returns `false` for overflow or a null `output`; writes zero on overflow.
bool try_mebibytes(usize count, scope usize* output) pure @safe
{
    return try_scale(count, bytes_per_mebibyte, output);
}

/// Attempts to convert gibibytes to bytes.
/// Returns `false` for overflow or a null `output`; writes zero on overflow.
bool try_gibibytes(usize count, scope usize* output) pure @safe
{
    return try_scale(count, bytes_per_gibibyte, output);
}

/// Attempts to convert tebibytes to bytes.
/// Returns `false` for overflow or a null `output`; writes zero on overflow.
bool try_tebibytes(usize count, scope usize* output) pure @safe
{
    return try_scale(count, bytes_per_tebibyte, output);
}

unittest
{
    assert(min(3, 7) == 3);
    assert(max(3, 7) == 7);
    assert(clamp(12, 0, 10) == 10);
}

unittest
{
    assert(!add_overflows(10, 20));
    assert(add_overflows(usize.max, 1));
    assert(!multiply_overflows(0, usize.max));
    assert(multiply_overflows(usize.max, 2));
    assert(grow_geometric(8, 9) == 16);
}

unittest
{
    assert(mebibytes(4) == 4 * 1_024 * 1_024);

    usize bytes = 1;
    assert(!try_tebibytes(usize.max, &bytes) && bytes == 0);
    assert(!try_mebibytes(1, null));
}
