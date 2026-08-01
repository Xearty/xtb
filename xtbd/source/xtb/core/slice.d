module xtb.core.slice;

import xtb.core.panic : require;

T[] subslice(T)(return scope T[] values, size_t offset, size_t count)
nothrow @system @nogc
{
    require(offset <= values.length, "slice offset out of bounds");
    require(count <= values.length - offset, "slice count out of bounds");
    return values[offset .. offset + count];
}

T[] drop(T)(return scope T[] values, size_t count)
pure nothrow @safe @nogc
{
    const amount = count < values.length ? count : values.length;
    return values[amount .. $];
}

T[] take(T)(return scope T[] values, size_t count)
pure nothrow @safe @nogc
{
    const amount = count < values.length ? count : values.length;
    return values[0 .. amount];
}

T[] dropLast(T)(return scope T[] values, size_t count)
pure nothrow @safe @nogc
{
    const amount = count < values.length ? count : values.length;
    return values[0 .. values.length - amount];
}

T[] takeLast(T)(return scope T[] values, size_t count)
pure nothrow @safe @nogc
{
    const amount = count < values.length ? count : values.length;
    return values[values.length - amount .. $];
}

ref T front(T)(return scope T[] values) nothrow @system @nogc
{
    require(values.length != 0, "front of empty slice");
    return values[0];
}

ref T back(T)(return scope T[] values) nothrow @system @nogc
{
    require(values.length != 0, "back of empty slice");
    return values[values.length - 1];
}

nothrow @nogc unittest
{
    int[5] storage = [1, 2, 3, 4, 5];
    assert(storage[].subslice(1, 3) == [2, 3, 4]);
    assert(storage[].drop(2) == [3, 4, 5]);
    assert(storage[].take(2) == [1, 2]);
    assert(storage[].dropLast(2) == [1, 2, 3]);
    assert(storage[].takeLast(2) == [4, 5]);
    storage[].front = 9;
    storage[].back = 7;
    assert(storage[0] == 9 && storage[4] == 7);
}
