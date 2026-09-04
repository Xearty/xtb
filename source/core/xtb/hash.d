module xtb.hash;

nothrow @nogc:

import xtb.types;

/// The two keys used by the default non-cryptographic hash function.
///
/// `HashSeed.init` is deterministic. A process-local seed avoids identical
/// layouts between runs, but this hash is not cryptographic; applications
/// accepting adversarial keys must select a stronger custom hash policy.
struct HashSeed
{
    u64 first = 0xA076_1D64_78BD_642F;
    u64 second = 0xE703_7ED1_A0B4_28DB;

    static HashSeed from_value(u64 value) pure nothrow @nogc @safe
    {
        return HashSeed(
            avalanche(value ^ 0x8EBC_6AF0_9C88_C6E3),
            avalanche(value ^ 0x5899_65CC_7537_4CC3),
        );
    }
}

private u64 avalanche(u64 value) pure @safe
{
    value ^= value >> 32;
    value *= 0xD6E8_FEB8_6659_FD93;
    value ^= value >> 32;
    value *= 0xD6E8_FEB8_6659_FD93;
    value ^= value >> 32;
    return value;
}

private u64 hash_bytes(scope String bytes, HashSeed seed) pure @safe
{
    u64 hash = seed.first ^ (cast(u64) bytes.length * 0x9E37_79B9_7F4A_7C15);
    foreach (value; bytes)
    {
        hash ^= cast(u8) value;
        hash *= 0x100_0000_01B3;
        hash ^= hash >> 29;
    }

    return avalanche(hash ^ seed.second);
}

/// Hashes the exact bytes in a `String`. Text normalization and case folding
/// are deliberately outside the hashing layer.
usize hash_value(scope String value, HashSeed seed = HashSeed.init) pure @safe
{
    return cast(usize) hash_bytes(value, seed);
}

/// Hashes integral and enum values without relying on `TypeInfo`.
usize hash_value(T)(const T value, HashSeed seed = HashSeed.init) pure @safe
if (
    is(T == bool)
    || is(T == i8)
    || is(T == u8)
    || is(T == i16)
    || is(T == u16)
    || is(T == i32)
    || is(T == u32)
    || is(T == i64)
    || is(T == u64)
    || is(T == char)
    || is(T == wchar)
    || is(T == dchar)
    || is(T == enum)
)
{
    const bits = cast(u64) value;
    const type_size_salt = cast(u64) T.sizeof * 0x9E37_79B9_7F4A_7C15;
    return cast(usize) avalanche(bits ^ seed.first ^ type_size_salt ^ seed.second);
}

/// Hashes a pointer by address. The result is meaningful only within the
/// process in which that address is valid.
/// `value` may be null.
usize hash_value(T)(scope T* value, HashSeed seed = HashSeed.init) pure @safe
{
    return cast(usize) avalanche(
        cast(usize) value ^ seed.first ^ seed.second,
    );
}

unittest
{
    enum TestKind : u8
    {
        first = 1,
        second = 2,
    }

    assert(hash_value(42) == hash_value(42));
    assert(hash_value(42, HashSeed.from_value(1)) != hash_value(42, HashSeed.from_value(2)));
    assert(hash_value(cast(u32) 42) != hash_value(cast(u64) 42));
    assert(hash_value(cast(String) "hello") == hash_value(cast(String) "hello"));
    assert(hash_value(cast(String) "hello") != hash_value(cast(String) "world"));
    assert(hash_value(TestKind.first) != hash_value(TestKind.second));

    i32 value = 0;
    assert(hash_value(&value) == hash_value(&value));
}
