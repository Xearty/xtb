module xtb.math.noise;

nothrow @nogc:

import core.internal.traits : hasElaborateDestructor;
import core.stdc.math : floorf, fmodf;
import xtb.core.containers.array;
import xtb.core.lifetime : move, moveEmplace, needsDeinit;
import xtb.core.memory : Allocator;
import xtb.core.panic : panic;

version (XTB_Checked) import xtb.core.panic : require;
import xtb.math.random : Random;
import xtb.math.scalar : smootherstep;

/// Owning, periodic one-dimensional value-noise lattice.
struct ValueNoise1D
{
nothrow @nogc:

    private Array!float values_;

    @disable this(this);
    @disable ref ValueNoise1D opAssign(ValueNoise1D source) return;

    static ValueNoise1D create(Allocator* allocator, size_t period, ulong seed, ulong stream = 0)
    {
        ValueNoise1D result;
        if (!tryCreate(allocator, period, seed, &result, stream))
            panic("ValueNoise1D allocation failed");
        return move(result);
    }

    static bool tryCreate(Allocator* allocator, size_t period, ulong seed,
        ValueNoise1D* output, ulong stream = 0)
    {
        version (XTB_Checked)
        {
            require(output !is null, "ValueNoise1D output pointer is null");
            require(allocator !is null, "ValueNoise1D requires an allocator");
            require(period != 0, "ValueNoise1D period must be nonzero");
            require(period <= 16_777_216, "ValueNoise1D period exceeds exact float integer range");
        }
        output.deinit();
        Array!float values = Array!float.create(allocator);
        moveEmplace(values, output.values_);
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

    void deinit()
    {
        values_.deinit();
    }

    size_t period() const pure @safe
    {
        return values_.length;
    }

    const(float)[] lattice() const return @system
    {
        return values_.slice;
    }

    float sample(float position) const @system
    {
        version (XTB_Checked)
        {
            require(values_.length != 0, "cannot sample empty ValueNoise1D");
            require(position == position && position <= float.max
                    && position >= -float.max, "ValueNoise1D position must be finite");
        }
        float wrapped = fmodf(position, cast(float) values_.length);
        if (wrapped < 0)
            wrapped += values_.length;
        const base = floorf(wrapped);
        const fraction = wrapped - base;
        const left = cast(size_t) base;
        const right = left + 1 == values_.length ? 0 : left + 1;
        const weight = smootherstep(0, 1, fraction);
        return values_[left] + (values_[right] - values_[left]) * weight;
    }
}

static assert(!hasElaborateDestructor!ValueNoise1D);
static assert(needsDeinit!ValueNoise1D);
static assert(!__traits(isCopyable, ValueNoise1D));

private extern (C) void* rejectingAllocation(
    void*,
    size_t,
    void*,
    size_t,
    size_t,
) @system
{
    return null;
}

private Allocator rejectingAllocator = &rejectingAllocation;

unittest
{
    import xtb.core.allocators.instrumented : AllocationRecord, InstrumentedAllocator;
    import xtb.core.allocators.malloc : mallocAllocator;

    AllocationRecord[4] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        mallocAllocator(),
        records[],
    );
    ValueNoise1D trackedNoise = ValueNoise1D.create(
        tracked.allocator,
        8,
        99,
    );
    assert(!tracked.clean());
    trackedNoise.deinit();
    assert(tracked.clean());
    assert(tracked.stats.invalidCalls == 0);

    ValueNoise1D a = ValueNoise1D.create(mallocAllocator(), 8, 1234);
    scope (exit)
        a.deinit();
    ValueNoise1D b = ValueNoise1D.create(mallocAllocator(), 8, 1234);
    scope (exit)
        b.deinit();
    assert(a.period == 8);
    foreach (index; 0 .. a.period)
        assert(a.lattice[index] == b.lattice[index]);
    foreach (position; [-9.75f, -1.25f, 0.0f, 3.125f, 17.5f])
        assert(a.sample(position) == a.sample(position + cast(float) a.period));
    assert(a.sample(2) == a.lattice[2]);
    ValueNoise1D rejected;
    assert(!ValueNoise1D.tryCreate(&rejectingAllocator, 8, 1, &rejected));
    assert(rejected.period == 0);
}
