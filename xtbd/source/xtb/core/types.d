module xtb.core.types;

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

pure nothrow @safe @nogc
T min(T)(T left, T right)
{
    return left < right ? left : right;
}

pure nothrow @safe @nogc
bool addOverflows(size_t left, size_t right)
{
    return right > size_t.max - left;
}

pure nothrow @safe @nogc
bool multiplyOverflows(size_t left, size_t right)
{
    return left != 0 && right > size_t.max / left;
}

nothrow @nogc unittest
{
    assert(!addOverflows(10, 20));
    assert(addOverflows(size_t.max, 1));
    assert(!multiplyOverflows(0, size_t.max));
    assert(multiplyOverflows(size_t.max, 2));
}
