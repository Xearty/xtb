module xtb.numeric;

nothrow @nogc:

version (XTB_Checked) import xtb.panic : require;

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

@safe
T clamp(T)(T value, T lower, T upper)
{
    version (XTB_Checked)
        require(lower <= upper, "invalid clamp range");
    return value < lower ? lower : value > upper ? upper : value;
}

pure @safe
size_t growGeometric(size_t current, size_t required)
{
    if (required <= current)
        return current;
    if (current == 0 || current > size_t.max / 2)
        return required;
    const doubled = current * 2;
    return doubled > required ? doubled : required;
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

private bool tryScale(size_t count, size_t multiplier, scope size_t* output) @safe
{
    if (output is null)
        return false;
    *output = 0;
    if (multiplyOverflows(count, multiplier))
        return false;
    *output = count * multiplier;
    return true;
}

private size_t scale(size_t count, size_t multiplier) @safe
{
    size_t result;
    const succeeded = tryScale(count, multiplier, &result);
    version (XTB_Checked)
        require(succeeded, "byte count overflow");
    return result;
}

size_t kibibytes(size_t count) @safe
{
    return scale(count, 1024);
}

size_t mebibytes(size_t count) @safe
{
    return scale(count, 1024 * 1024);
}

size_t gibibytes(size_t count) @safe
{
    return scale(count, 1024UL * 1024 * 1024);
}

size_t tebibytes(size_t count) @safe
{
    return scale(count, 1024UL * 1024 * 1024 * 1024);
}

bool tryKibibytes(size_t count, scope size_t* output) @safe
{
    return tryScale(count, 1024, output);
}

bool tryMebibytes(size_t count, scope size_t* output) @safe
{
    return tryScale(count, 1024 * 1024, output);
}

bool tryGibibytes(size_t count, scope size_t* output) @safe
{
    return tryScale(count, 1024UL * 1024 * 1024, output);
}

bool tryTebibytes(size_t count, scope size_t* output) @safe
{
    return tryScale(count, 1024UL * 1024 * 1024 * 1024, output);
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
    assert(growGeometric(8, 9) == 16);
    assert(mebibytes(4) == 4 * 1024 * 1024);
    size_t bytes = 1;
    assert(!tryTebibytes(size_t.max, &bytes) && bytes == 0);
    assert(!tryMebibytes(1, null));
}
