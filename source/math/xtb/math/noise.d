module xtb.math.noise;

nothrow @nogc:

import core.attribute;
import core.internal.traits;
import core.stdc.math;

import xtb.containers.array;
import xtb.lifetime;
import xtb.math.random;
import xtb.math.scalar;
import xtb.memory;
import xtb.panic;
import xtb.types;

/// Owning, periodic one-dimensional value-noise lattice.
@mustuse struct ValueNoise1D
{
    nothrow @nogc:

    /// Lattice storage. A live noise value contains 1..16_777_216 samples.
    Array!f32 values;

    @disable this(this);
    @disable ref ValueNoise1D opAssign(ValueNoise1D source) return;

    /// `allocator` must point to a valid allocator.
    static ValueNoise1D create(Allocator* allocator, usize period, u64 seed, u64 stream = 0)
    {
        ValueNoise1D result;
        if (!ValueNoise1D.try_create(allocator, period, seed, &result, stream))
            panic("ValueNoise1D allocation failed");

        return move(result);
    }

    /// `allocator` and `output` must not be null.
    ///
    /// Any value already owned by `output` is deinitialized before allocation.
    /// On failure, `output` remains `ValueNoise1D.init`.
    static bool try_create(
        Allocator* allocator,
        usize period,
        u64 seed,
        scope ValueNoise1D* output,
        u64 stream = 0,
    )
    {
        require(output !is null, "ValueNoise1D output pointer is null");
        require(allocator !is null, "ValueNoise1D requires an allocator");
        require(period != 0, "ValueNoise1D period must be nonzero");
        require(period <= 16_777_216, "ValueNoise1D period exceeds exact f32 integer range");

        output.deinit();

        ValueNoise1D temporary;
        Array!f32 values = Array!f32.create(allocator);
        move_emplace(values, temporary.values);
        if (!temporary.values.try_resize(period))
        {
            temporary.deinit();
            return false;
        }

        Random random = Random.seeded(seed, stream);
        foreach (index; 0 .. period)
            temporary.values[index] = random.between(-1, 1);

        move_emplace(temporary, *output);
        return true;
    }

    void deinit()
    {
        this.values.deinit();
    }

    usize period() const pure @safe
    {
        return this.values.length;
    }

    inout(f32)[] lattice() inout return @system
    {
        return this.values.slice;
    }

    f32 sample(f32 position) const @system
    {
        require(this.values.length != 0, "cannot sample empty ValueNoise1D");
        require(position.is_finite, "ValueNoise1D position must be finite");

        f32 wrapped = fmodf(position, cast(f32) this.values.length);
        if (wrapped < 0) wrapped += this.values.length;

        const base = floorf(wrapped);
        const fraction = wrapped - base;
        const left = cast(usize) base;
        const right = left + 1 == this.values.length ? 0 : left + 1;
        const weight = smootherstep(0, 1, fraction);
        return this.values[left] + (this.values[right] - this.values[left]) * weight;
    }
}

static assert(!hasElaborateDestructor!ValueNoise1D);
static assert(needs_deinit!ValueNoise1D);
static assert(!__traits(isCopyable, ValueNoise1D));

version (unittest)
{
    import xtb.allocators.instrumented;
    import xtb.allocators.malloc;
}

private extern (C) void* rejecting_allocation(
    void*,
    usize,
    void*,
    usize,
    usize,
) @system
{
    return null;
}

unittest
{
    AllocationRecord[4] records;
    InstrumentedAllocator tracked = InstrumentedAllocator.create(
        malloc_allocator(),
        records[],
    );
    ValueNoise1D tracked_noise = ValueNoise1D.create(
        tracked.allocator,
        8,
        99,
    );
    assert(!tracked.clean());

    Allocator rejecting_allocator = &rejecting_allocation;
    assert(!ValueNoise1D.try_create(&rejecting_allocator, 8, 1, &tracked_noise));
    assert(tracked_noise.period == 0);
    assert(tracked.clean());
    assert(tracked.stats.invalid_calls == 0);
}

unittest
{
    ValueNoise1D a = ValueNoise1D.create(malloc_allocator(), 8, 1234);
    scope (exit) a.deinit();
    ValueNoise1D b = ValueNoise1D.create(malloc_allocator(), 8, 1234);
    scope (exit) b.deinit();

    assert(a.period == 8);
    foreach (index; 0 .. a.period)
        assert(a.lattice[index] == b.lattice[index]);
    foreach (position; [-9.75f, -1.25f, 0.0f, 3.125f, 17.5f])
        assert(a.sample(position) == a.sample(position + cast(f32) a.period));
    assert(a.sample(2) == a.lattice[2]);
}
