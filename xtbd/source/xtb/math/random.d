module xtb.math.random;

import xtb.core.types : u32, u64;

/// Small deterministic PCG-XSH-RR generator. Its sequence is stable API.
struct Random
{
pure nothrow @safe @nogc:

    private u64 state_;
    private u64 increment_;

    static Random seeded(u64 seed, u64 stream = 0)
    {
        Random result;
        result.increment_ = (stream << 1) | 1;
        result.nextU32();
        result.state_ += seed;
        result.nextU32();
        return result;
    }

    u32 nextU32()
    {
        const oldState = state_;
        state_ = oldState * 6_364_136_223_846_793_005UL + increment_;
        const shifted = cast(u32)(((oldState >> 18) ^ oldState) >> 27);
        const rotation = cast(u32)(oldState >> 59);
        return (shifted >> rotation) | (shifted << ((-rotation) & 31));
    }

    u32 below(u32 bound)
    {
        assert(bound != 0, "random bound must be nonzero");
        const threshold = -bound % bound;
        for (;;)
        {
            const value = nextU32();
            if (value >= threshold)
                return value % bound;
        }
    }

    /// Uniform in [0, 1), using the 24 significant bits representable by float.
    float unit()
    {
        return cast(float)(nextU32() >> 8) * (1.0f / 16_777_216.0f);
    }

    float between(float lower, float upper)
    {
        assert(lower <= upper, "invalid random range");
        return lower + (upper - lower) * unit();
    }
}

nothrow @safe @nogc unittest
{
    Random a = Random.seeded(42, 54);
    Random b = Random.seeded(42, 54);
    const u32[5] expected = [
        2_707_161_783U, 2_068_313_097U, 3_122_475_824U, 2_211_639_955U,
        3_215_226_955U
    ];
    foreach (value; expected)
        assert(a.nextU32() == value);
    a = Random.seeded(42, 54);
    foreach (_; 0 .. 32)
        assert(a.nextU32() == b.nextU32());
    Random range = Random.seeded(1);
    foreach (_; 0 .. 100)
    {
        const value = range.below(7);
        assert(value < 7);
        const realValue = range.unit();
        assert(realValue >= 0 && realValue < 1);
    }
}
