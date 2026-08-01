module xtb.core.option;

nothrow @nogc:

import core.lifetime : move, moveEmplace;
import xtb.core.panic : require;

version (unittest) private struct TrackedOptionValue
{
nothrow @nogc:

    int* destructions;
    bool armed;

    @disable this(this);

    ~this()
    {
        if (armed)
            ++*destructions;
    }
}

struct Option(T)
{
nothrow @nogc:

    private bool present_;
    private T value_;

    static if (!__traits(isCopyable, T))
        @disable this(this);

    static Option none()
    {
        return Option.init;
    }

    static Option some(T value)
    {
        Option result;
        result.set(move(value));
        return result;
    }

    bool isSome() const pure @safe
    {
        return present_;
    }

    bool isNone() const pure @safe
    {
        return !present_;
    }

    /// This function exists only for compatibility with range-oriented generic
    /// code. Use `isNone` when directly inspecting an `Option`.
    bool empty() const pure @safe
    {
        return isNone;
    }

    ref T value() return @system
    {
        require(present_, "empty Option has no value");
        return value_;
    }

    ref const(T) value() const return @system
    {
        require(present_, "empty Option has no value");
        return value_;
    }

    T* pointer() return @system
    {
        return present_ ? &value_ : null;
    }

    const(T)* pointer() const return @system
    {
        return present_ ? &value_ : null;
    }

    package(xtb) ref T storage() return @system
    {
        return value_;
    }

    package(xtb) void markPresent()
    {
        present_ = true;
    }
}

void set(T)(ref Option!T option, T value)
{
    move(value, option.value_);
    option.present_ = true;
}

void reset(T)(ref Option!T option)
{
    T empty;
    move(empty, option.value_);
    option.present_ = false;
}

T take(T)(ref Option!T option)
{
    require(option.present_, "cannot take an empty Option");
    T result = void;
    moveEmplace(option.value_, result);
    static if (__traits(isPOD, T))
        option.value_ = T.init;
    option.present_ = false;
    return result;
}

Option!T some(T)(T value)
{
    return Option!T.some(move(value));
}

Option!T none(T)()
{
    return Option!T.none();
}

unittest
{
    import xtb.core.memory : mallocAllocator;
    import xtb.core.string : StringBuf, append, equal;

    Option!int number;
    assert(number.isNone && number.empty);
    assert(number.pointer is null);
    number.set(42);
    assert(number.isSome);
    assert(number.value == 42);
    assert(number.pointer is &number.value());
    assert(number.take == 42);
    assert(number.isNone);
    assert(number.pointer is null);

    Option!int copied = some(7);
    Option!int copiedAgain = copied;
    copied.set(9);
    assert(copied.value == 9);
    assert(copiedAgain.value == 7);
    copied.reset();
    assert(copied.isNone);

    StringBuf source = StringBuf.fromString(mallocAllocator(), "owned");
    Option!StringBuf text = some(move(source));
    assert(source.allocator is null);
    assert(text.value.view.equal("owned"));
    text.value.append(" value");
    StringBuf extracted = text.take();
    assert(text.isNone);
    assert(extracted.view.equal("owned value"));
    text.set(move(extracted));
    text.reset();
    assert(text.isNone);

    int destructions;
    {
        TrackedOptionValue first = TrackedOptionValue(&destructions, true);
        Option!TrackedOptionValue tracked = some(move(first));
        tracked.reset();
        assert(destructions == 1);

        TrackedOptionValue second = TrackedOptionValue(&destructions, true);
        tracked.set(move(second));
        TrackedOptionValue taken = tracked.take();
        assert(tracked.isNone);
        assert(destructions == 1);
    }
    assert(destructions == 2);

    static assert(!__traits(compiles, (ref Option!StringBuf value) { Option!StringBuf copy = value; }));
}
