module tests.zero_cost.vector_indexing;

nothrow @nogc @safe:

import xtb.math.vector;
import xtb.types;

private mixin template IndexingProbe(V)
{
    nothrow @nogc @safe:

    alias Components = f32[V.component_count];

    pragma(inline, false)
    pragma(mangle, V.stringof ~ "_indexed_read")
    extern (C) f32 indexed_read(scope const(V)* vector, usize index)
    {
        return (*vector)[index];
    }

    pragma(inline, false)
    pragma(mangle, V.stringof ~ "_array_read")
    extern (C) f32 array_read(scope const(Components)* values, usize index)
    {
        return (*values)[index];
    }

    pragma(inline, false)
    pragma(mangle, V.stringof ~ "_constant_read")
    extern (C) f32 constant_read(scope const(V)* vector)
    {
        return (*vector)[V.component_count - 1];
    }

    pragma(inline, false)
    pragma(mangle, V.stringof ~ "_array_constant_read")
    extern (C) f32 array_constant_read(scope const(Components)* values)
    {
        return (*values)[V.component_count - 1];
    }

    pragma(inline, false)
    pragma(mangle, V.stringof ~ "_indexed_write")
    extern (C) void indexed_write(scope V* vector, usize index, f32 value)
    {
        (*vector)[index] = value;
    }

    pragma(inline, false)
    pragma(mangle, V.stringof ~ "_array_write")
    extern (C) void array_write(scope Components* values, usize index, f32 value)
    {
        (*values)[index] = value;
    }

    pragma(inline, false)
    pragma(mangle, V.stringof ~ "_constant_write")
    extern (C) void constant_write(scope V* vector, f32 value)
    {
        (*vector)[V.component_count - 1] = value;
    }

    pragma(inline, false)
    pragma(mangle, V.stringof ~ "_array_constant_write")
    extern (C) void array_constant_write(scope Components* values, f32 value)
    {
        (*values)[V.component_count - 1] = value;
    }

    bool check()
    {
        V vector;
        Components values = 0;

        foreach (index; 0 .. V.component_count)
        {
            const f32 value = cast(f32)(index + 1);
            indexed_write(&vector, index, value);
            array_write(&values, index, value);
            if (indexed_read(&vector, index) != array_read(&values, index)) return false;
        }

        constant_write(&vector, 9);
        array_constant_write(&values, 9);
        return constant_read(&vector) == array_constant_read(&values)
            && indexed_read(&vector, V.component_count - 1) == 9;
    }
}

mixin IndexingProbe!Vector2 vector2;
mixin IndexingProbe!Vector3 vector3;
mixin IndexingProbe!Vector4 vector4;

extern (C) i32 main()
{
    return vector2.check() && vector3.check() && vector4.check() ? 0 : 1;
}
