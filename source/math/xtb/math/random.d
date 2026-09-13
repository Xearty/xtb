module xtb.math.random;

nothrow @nogc @safe:

import xtb.math.scalar;
import xtb.panic;
import xtb.types;

/// Small deterministic PCG-XSH-RR generator. Its sequence is stable API.
struct Random
{
nothrow @nogc @safe:

    u64 state;
    u64 increment;

    static Random seeded(u64 seed, u64 stream = 0)
    {
        Random result = Random.init;
        result.increment = (stream << 1) | 1;
        result.next_u32();
        result.state += seed;
        result.next_u32();
        return result;
    }

    u32 next_u32()
    {
        const old_state = this.state;
        this.state = old_state * 6_364_136_223_846_793_005UL + this.increment;
        const shifted = cast(u32)(((old_state >> 18) ^ old_state) >> 27);
        const rotation = cast(u32)(old_state >> 59);
        return (shifted >> rotation) | (shifted << ((-rotation) & 31));
    }

    u32 below(u32 bound)
    {
        require(bound != 0, "random bound must be nonzero");
        const threshold = -bound % bound;
        for (;;)
        {
            const value = this.next_u32();
            if (value >= threshold) return value % bound;
        }
    }

    /// Uniform in [0, 1), using the 24 significant bits representable by `f32`.
    f32 unit()
    {
        return cast(f32)(this.next_u32() >> 8) * (1.0f / 16_777_216.0f);
    }

    f32 between(f32 lower, f32 upper)
    {
        require(
            lower.is_finite && upper.is_finite && lower <= upper,
            "random range must be finite and ordered",
        );
        if (lower == upper) return lower;

        const t = this.unit();
        if (lower < 0 && upper > 0) return lower * (1 - t) + upper * t;

        return lower + (upper - lower) * t;
    }
}

unittest
{
    Random a = Random.seeded(42, 54);
    Random b = Random.seeded(42, 54);
    const u32[5] expected = [
        2_707_161_783U,
        2_068_313_097U,
        3_122_475_824U,
        2_211_639_955U,
        3_215_226_955U,
    ];
    foreach (value; expected) assert(a.next_u32() == value);

    a = Random.seeded(42, 54);
    foreach (_; 0 .. 32) assert(a.next_u32() == b.next_u32());

    Random range = Random.seeded(1);
    foreach (_; 0 .. 100)
    {
        const value = range.below(7);
        assert(value < 7);
        const real_value = range.unit();
        assert(real_value >= 0 && real_value < 1);
    }
    foreach (_; 0 .. 100)
    {
        const value = range.between(-f32.max, f32.max);
        assert(value.is_finite && value >= -f32.max && value <= f32.max);
    }
    assert(range.between(7, 7) == 7);
}
