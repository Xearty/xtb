module xtb.core.hash;

nothrow @nogc:

import xtb.core.types : String;

/// The two keys used by the default non-cryptographic hash function.
///
/// `HashSeed.init` is deterministic. A process-local seed avoids identical
/// layouts between runs, but this hash is not cryptographic; applications
/// accepting adversarial keys must select a stronger custom hash policy.
struct HashSeed
{
    ulong first = 0xa076_1d64_78bd_642f;
    ulong second = 0xe703_7ed1_a0b4_28db;

    static HashSeed fromValue(ulong value) pure nothrow @safe @nogc
    {
        return HashSeed(
            avalanche(value ^ 0x8ebc_6af0_9c88_c6e3),
            avalanche(value ^ 0x5899_65cc_7537_4cc3),
        );
    }
}

private ulong avalanche(ulong value) pure @safe
{
    value ^= value >> 32;
    value *= 0xd6e8_feb8_6659_fd93;
    value ^= value >> 32;
    value *= 0xd6e8_feb8_6659_fd93;
    value ^= value >> 32;
    return value;
}

private ulong hashBytes(scope const(char)[] bytes, HashSeed seed) pure @safe
{
    ulong hash = seed.first ^ (cast(ulong) bytes.length * 0x9e37_79b9_7f4a_7c15);
    foreach (value; bytes)
    {
        hash ^= cast(ubyte) value;
        hash *= 0x100_0000_01b3;
        hash ^= hash >> 29;
    }
    return avalanche(hash ^ seed.second);
}

/// Hashes the exact bytes in a `String`. Text normalization and case folding
/// are deliberately outside the hashing layer.
size_t hashValue(scope String value, HashSeed seed = HashSeed.init) pure @safe
{
    return cast(size_t) hashBytes(value, seed);
}

/// Hashes integral and enum values without relying on `TypeInfo`.
size_t hashValue(T)(scope const T value, HashSeed seed = HashSeed.init) pure @safe
        if (is(T == bool) || is(T == byte) || is(T == ubyte) ||
        is(T == short) || is(T == ushort) || is(T == int) ||
        is(T == uint) || is(T == long) || is(T == ulong) ||
        is(T == char) || is(T == wchar) || is(T == dchar) ||
        is(T == enum))
{
    const bits = cast(ulong) value;
    return cast(size_t) avalanche(bits ^ seed.first ^
            (cast(ulong) T.sizeof * 0x9e37_79b9_7f4a_7c15) ^ seed.second);
}

/// Hashes a pointer by address. The result is meaningful only within the
/// process in which that address is valid.
size_t hashValue(T)(scope T* value, HashSeed seed = HashSeed.init) pure @safe
{
    return cast(size_t) avalanche(
        cast(size_t) value ^ seed.first ^ seed.second,
    );
}

unittest
{
    enum TestKind : ubyte
    {
        first = 1,
        second = 2,
    }

    assert(hashValue(42) == hashValue(42));
    assert(hashValue(42, HashSeed.fromValue(1)) !=
            hashValue(42, HashSeed.fromValue(2)));
    assert(hashValue(cast(uint) 42) != hashValue(cast(ulong) 42));
    assert(hashValue(cast(String) "hello") == hashValue(cast(String) "hello"));
    assert(hashValue(cast(String) "hello") != hashValue(cast(String) "world"));
    assert(hashValue(TestKind.first) != hashValue(TestKind.second));

    int value;
    assert(hashValue(&value) == hashValue(&value));
}
