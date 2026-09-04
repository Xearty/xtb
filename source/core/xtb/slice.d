module xtb.slice;

nothrow @nogc:

import xtb.panic;
import xtb.types;

/// Returns the borrowed region beginning at `offset` with `count` elements.
/// `offset` and `count` must describe a region within `values`.
T[] subslice(T)(
    return scope T[] values,
    usize offset,
    usize count,
) @system
{
    require(offset <= values.length, "slice offset is out of bounds");
    require(count <= values.length - offset, "slice count is out of bounds");
    return values[offset .. offset + count];
}

T[] drop(T)(return scope T[] values, usize count) pure @safe
{
    const amount = count < values.length ? count : values.length;
    return values[amount .. $];
}

T[] take(T)(return scope T[] values, usize count) pure @safe
{
    const amount = count < values.length ? count : values.length;
    return values[0 .. amount];
}

T[] drop_last(T)(return scope T[] values, usize count) pure @safe
{
    const amount = count < values.length ? count : values.length;
    return values[0 .. values.length - amount];
}

T[] take_last(T)(return scope T[] values, usize count) pure @safe
{
    const amount = count < values.length ? count : values.length;
    return values[values.length - amount .. $];
}

/// Returns the first element by reference. `values` must not be empty.
ref T front(T)(return scope T[] values) @system
{
    require(values.length != 0, "cannot access the front of an empty slice");
    return values[0];
}

/// Returns the last element by reference. `values` must not be empty.
ref T back(T)(return scope T[] values) @system
{
    require(values.length != 0, "cannot access the back of an empty slice");
    return values[values.length - 1];
}

unittest
{
    i32[5] storage = [1, 2, 3, 4, 5];
    assert(storage[].subslice(1, 3) == [2, 3, 4]);
    assert(storage[].drop(2) == [3, 4, 5]);
    assert(storage[].take(2) == [1, 2]);
    assert(storage[].drop_last(2) == [1, 2, 3]);
    assert(storage[].take_last(2) == [4, 5]);
}

unittest
{
    i32[5] storage = [1, 2, 3, 4, 5];
    storage[].front = 9;
    storage[].back = 7;
    assert(storage[0] == 9 && storage[4] == 7);
}
