module xtb.core.types;

nothrow @nogc:

alias u8 = ubyte;
alias u16 = ushort;
alias u32 = uint;
alias u64 = ulong;

alias i8 = byte;
alias i16 = short;
alias i32 = int;
alias i64 = long;

alias usize = size_t;
alias isize = ptrdiff_t;

alias f32 = float;
alias f64 = double;

alias String = const(char)[];

pure @safe
T min(T)(T left, T right)
{
    return left < right ? left : right;
}

pure @safe
T max(T)(T left, T right)
{
    return left > right ? left : right;
}

pure @safe
T clamp(T)(T value, T lower, T upper)
{
    assert(lower <= upper, "invalid clamp range");
    return value < lower ? lower : value > upper ? upper : value;
}

pure @safe
bool growGeometric(size_t current, size_t required, size_t* result)
{
    if (required <= current)
    {
        *result = current;
        return true;
    }
    if (current == 0)
    {
        *result = required;
        return true;
    }
    if (current > size_t.max / 2)
    {
        *result = required;
        return true;
    }
    const doubled = current * 2;
    *result = doubled > required ? doubled : required;
    return true;
}

pure @safe
bool scaleBytes(size_t count, size_t multiplier, size_t* result)
{
    if (multiplyOverflows(count, multiplier))
        return false;
    *result = count * multiplier;
    return true;
}

pure @safe bool kibibytes(size_t count, size_t* result)
{
    return scaleBytes(count, 1024, result);
}

pure @safe bool mebibytes(size_t count, size_t* result)
{
    return scaleBytes(count, 1024 * 1024, result);
}

pure @safe bool gibibytes(size_t count, size_t* result)
{
    return scaleBytes(count, 1024UL * 1024 * 1024, result);
}

pure @safe bool tebibytes(size_t count, size_t* result)
{
    return scaleBytes(count, 1024UL * 1024 * 1024 * 1024, result);
}

pure @safe
bool addOverflows(size_t left, size_t right)
{
    return right > size_t.max - left;
}

pure @safe
bool multiplyOverflows(size_t left, size_t right)
{
    return left != 0 && right > size_t.max / left;
}

unittest
{
    assert(!addOverflows(10, 20));
    assert(addOverflows(size_t.max, 1));
    assert(!multiplyOverflows(0, size_t.max));
    assert(multiplyOverflows(size_t.max, 2));
    assert(min(3, 7) == 3);
    assert(max(3, 7) == 7);
    assert(clamp(12, 0, 10) == 10);
    size_t bytes;
    assert(mebibytes(4, &bytes) && bytes == 4 * 1024 * 1024);
    assert(!tebibytes(size_t.max, &bytes));
}
