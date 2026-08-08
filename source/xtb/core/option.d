module xtb.core.option;

nothrow @nogc:

import core.attribute : mustuse;
import core.lifetime : forward, move, moveEmplace;
import xtb.core.panic : panic;
import xtb.core.types : String;
version (XTB_Checked)
    import xtb.core.panic : require;

private enum bool isOptionType(T) = is(T == Option!Value, Value);

/// Explicit absence token accepted by Option construction and assignment.
struct None
{
}


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

/// An optional BetterC value. Option.init is absent.
@mustuse struct Option(T)
{
nothrow @nogc:

    static assert(!is(T == void), "Option value type cannot be void");

    private bool present_;
    private T value_;

    static if (!__traits(isCopyable, T))
        @disable this(this);

    /// Explicitly constructs an absent Option from `none()`.
    this(None)
    {
    }

    /// Explicitly clears this Option through `option = none()`.
    ref Option opAssign(None) return
    {
        reset();
        return this;
    }


    static Option none()
    {
        return Option.init;
    }

    static Option some(T value)
    {
        Option result;
        move(value, result.value_);
        result.present_ = true;
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

    /// Converts to true exactly when this Option contains a value.
    bool opCast(U : bool)() const pure @safe
    {
        return isSome;
    }

    /// This function exists only for compatibility with range-oriented generic
    /// code. Use `isNone` when directly inspecting an `Option`.
    bool empty() const pure @safe
    {
        return isNone;
    }

    ref inout(T) value() inout return @system
    {
        version (XTB_Checked)
            require(present_, "empty Option has no value");
        return value_;
    }

    inout(T)* pointer() inout return @system
    {
        return present_ ? &value_ : null;
    }


    /// Destroys the current value, if any, and makes this Option absent.
    void reset()
    {
        T emptyValue;
        move(emptyValue, value_);
        present_ = false;
    }

    /// Transfers the current value out and leaves this Option absent.
    T take()
    {
        version (XTB_Checked)
            require(present_, "cannot take an empty Option");
        T result = void;
        moveEmplace(value_, result);
        static if (__traits(isPOD, T))
            value_ = T.init;
        present_ = false;
        return result;
    }

    /// Transfers the value out or panics when this Option is absent.
    ///
    /// Unlike checked contracts, this state check is always enabled.
    T unwrap()
    {
        if (!present_)
            panic("called Option.unwrap() on none");
        return take();
    }

    /// Transfers the value out or panics with `message` when absent.
    ///
    /// Unlike checked contracts, this state check is always enabled.
    T expect(String message)
    {
        if (!present_)
            panic(message);
        return take();
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

Option!T some(T)(T value)
{
    return Option!T.some(move(value));
}

None none()
{
    return None.init;
}

/// Introduces `some` and `none` aliases for the enclosing function's Option type.
mixin template OptionReturns()
{
    alias some = typeof(return).some;
    alias none = typeof(return).none;
}

/// Transforms a present value and preserves absence.
auto map(alias transform, T, Args...)(
    Option!T option,
    auto ref Args args,
)
{
    alias U = typeof(transform(option.take(), forward!args));
    static assert(!is(U == void), "Option.map transform must return a value");

    if (option.isNone)
        return Option!U.none();

    U value = transform(option.take(), forward!args);
    return Option!U.some(move(value));
}

/// Chains an Option-producing operation after a present Option.
auto andThen(alias transform, T, Args...)(
    Option!T option,
    auto ref Args args,
)
{
    alias Next = typeof(transform(option.take(), forward!args));
    static assert(
        isOptionType!Next,
        "Option.andThen transform must return Option",
    );

    if (option.isNone)
        return Next.none();
    return transform(option.take(), forward!args);
}

/// Produces an alternate Option when this Option is absent.
auto orElse(alias transform, T, Args...)(
    Option!T option,
    auto ref Args args,
)
{
    alias Next = typeof(transform(forward!args));
    static assert(
        is(Next == Option!T),
        "Option.orElse transform must return the same Option type",
    );

    if (option.isNone)
        return transform(forward!args);
    return Next.some(option.take());
}

version (unittest) private Option!int optionTestReturn(bool present)
{
    mixin OptionReturns;
    if (!present)
        return none();
    return some(12);
}

unittest
{
    import xtb.core.memory : mallocAllocator;
    import xtb.core.string;

    // Option construction is explicit: raw values do not implicitly become Some.
    static assert(!__traits(compiles, Option!int(13)));
    static assert(!__traits(compiles, () { Option!int value = 13; }));
    static assert(!__traits(compiles, () { Option!int value; value = 13; }));

    Option!int number;
    Option!int declaredSome = some(13);
    Option!int declaredNone = none();
    assert(declaredSome.isSome && declaredSome.value == 13);
    assert(declaredNone.isNone);
    declaredSome = none();
    assert(declaredSome.isNone);
    declaredNone = some(17);
    assert(declaredNone.isSome && declaredNone.value == 17);

    assert(number.isNone && number.empty);
    assert(!number);
    assert(number.pointer is null);
    number = some(42);
    assert(number.isSome && number);
    assert(number.value == 42);
    assert(number.pointer is &number.value());
    assert(number.take == 42);
    assert(number.isNone);
    assert(number.pointer is null);

    number = some(51);
    assert(number.unwrap() == 51);
    assert(number.isNone);
    number = some(52);
    assert(number.expect("expected a number") == 52);
    assert(number.isNone);

    Option!int copied = some(7);
    Option!int copiedAgain = copied;
    copied = some(9);
    assert(copied.value == 9);
    assert(copiedAgain.value == 7);
    copied.reset();
    assert(copied.isNone);

    const Option!int readOnly = some(5);
    static assert(is(typeof(readOnly.value()) == const(int)));
    static assert(is(typeof(readOnly.pointer()) == const(int)*));
    immutable Option!int immutableValue = Option!int.some(6);
    static assert(is(typeof(immutableValue.value()) == immutable(int)));
    static assert(is(typeof(immutableValue.pointer()) == immutable(int)*));

    assert(optionTestReturn(false).isNone);
    assert(optionTestReturn(true).value == 12);

    StringBuf source = StringBuf.fromString(mallocAllocator(), "owned");
    Option!StringBuf text = some(move(source));
    assert(source.allocator is null);
    assert(text.value == "owned");
    text.value.append(" value");
    StringBuf extracted = text.unwrap();
    assert(text.isNone);
    assert(extracted == "owned value");
    text = some(move(extracted));
    text.reset();
    assert(text.isNone);

    int destructions;
    {
        TrackedOptionValue first = TrackedOptionValue(&destructions, true);
        Option!TrackedOptionValue tracked = some(move(first));
        tracked.reset();
        assert(destructions == 1);

        TrackedOptionValue second = TrackedOptionValue(&destructions, true);
        tracked = some(move(second));
        TrackedOptionValue taken = tracked.take();
        assert(tracked.isNone);
        assert(destructions == 1);
    }
    assert(destructions == 2);

    static assert(!__traits(compiles,
        (ref Option!StringBuf value)
        {
            Option!StringBuf copy = value;
        }));

    Option!(int*) presentNull = some(cast(int*) null);
    assert(presentNull.isSome && presentNull.value is null);
    presentNull = none();
    assert(presentNull.isNone);
}

unittest
{
    auto mapped = some(4).map!(value => value * 3);
    assert(mapped.isSome && mapped.value == 12);
    assert(Option!int.none().map!(value => value * 3).isNone);

    auto chained = some(4).andThen!(value => value > 0 ? some(value + 1) : Option!int.none());
    assert(chained.isSome && chained.value == 5);

    int fallbackCalls;
    auto retained = some(4).orElse!(() { ++fallbackCalls; return some(9); });
    assert(retained.value == 4 && fallbackCalls == 0);
    auto recovered = Option!int.none().orElse!(() { ++fallbackCalls; return some(9); });
    assert(recovered.value == 9 && fallbackCalls == 1);

    int offset = 10;
    auto captured = some(2).map!(value => value + offset);
    assert(captured.value == 12);
}
