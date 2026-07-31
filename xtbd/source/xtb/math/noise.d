module xtb.math.noise;

nothrow @nogc:

import core.stdc.math : floorf;
import xtb.core.array : Array, tryResize;
import xtb.core.memory : Allocator;
import xtb.core.panic : panic, require;
import xtb.math.random : Random;
import xtb.math.scalar : smootherstep;

/// Owning, periodic one-dimensional value-noise lattice.
struct ValueNoise1D
{
    nothrow @nogc:

    private Array!float values_;

    @disable this(this);

    static ValueNoise1D create(Allocator* allocator, size_t period, ulong seed,
        ulong stream = 0)
    {
        ValueNoise1D result;
        if (!tryCreate(allocator, period, seed, &result, stream))
            panic("ValueNoise1D allocation failed");
        return result;
    }

    static bool tryCreate(Allocator* allocator, size_t period, ulong seed,
        ValueNoise1D* output, ulong stream = 0)
    {
        require(output !is null, "ValueNoise1D output pointer is null");
        require(allocator !is null, "ValueNoise1D requires an allocator");
        require(period != 0, "ValueNoise1D period must be nonzero");
        output.deinit();
        output.values_ = Array!float.create(allocator);
        if (!output.values_.tryResize(period))
        {
            output.deinit();
            return false;
        }
        Random random = Random.seeded(seed, stream);
        foreach (index; 0 .. period)
            output.values_[index] = random.between(-1, 1);
        return true;
    }

    ~this() { deinit(); }

    void deinit() { values_.deinit(); }

    size_t period() const pure @safe { return values_.length; }

    const(float)[] lattice() const return @system
    {
        return values_.slice;
    }

    float sample(float position) const @system
    {
        require(values_.length != 0, "cannot sample empty ValueNoise1D");
        const base = floorf(position);
        const fraction = position - base;
        const left = wrapIndex(cast(long) base, values_.length);
        const right = left + 1 == values_.length ? 0 : left + 1;
        const weight = smootherstep(0, 1, fraction);
        return values_[left] + (values_[right] - values_[left]) * weight;
    }
}

private pure @safe size_t wrapIndex(long index, size_t period)
{
    const signedPeriod = cast(long) period;
    const remainder = index % signedPeriod;
    return cast(size_t)(remainder < 0 ? remainder + signedPeriod : remainder);
}

unittest
{
    import xtb.core.memory : mallocAllocator;
    ValueNoise1D a = ValueNoise1D.create(mallocAllocator(), 8, 1234);
    ValueNoise1D b = ValueNoise1D.create(mallocAllocator(), 8, 1234);
    assert(a.period == 8);
    foreach (index; 0 .. a.period)
        assert(a.lattice[index] == b.lattice[index]);
    foreach (position; [-9.75f, -1.25f, 0.0f, 3.125f, 17.5f])
        assert(a.sample(position) == a.sample(position + cast(float) a.period));
    assert(a.sample(2) == a.lattice[2]);
}
