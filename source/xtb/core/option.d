module xtb.core.option;

nothrow @nogc:

import core.attribute : mustuse;
import core.internal.traits : hasElaborateCopyConstructor, hasElaborateDestructor;
import core.lifetime : forward;
import xtb.core.lifetime : deinitValue = deinit, move, moveEmplace, needsDeinit;
import xtb.core.panic : panic;
import xtb.core.types : String;

version (XTB_Checked) import xtb.core.panic : require;

private enum bool isOptionType(T) = is(T == Option!Value, Value);

private template OptionValue(T)
{
    static if (is(T == Option!Value, Value))
        alias OptionValue = Value;
}

private enum bool isMonadicValue(T) = !needsDeinit!T &&
    !hasElaborateDestructor!T && !hasElaborateCopyConstructor!T;

/// Explicit absence token accepted by Option construction and assignment.
struct None
{
}

version (unittest) private struct TrackedOptionValue
{
nothrow @nogc:

    int* deinits;
    bool armed;

    @disable this(this);

    void deinit()
    {
        if (armed)
        {
            ++*deinits;
            armed = false;
        }
    }
}

version (unittest) private struct DestructorOptionValue
{
nothrow @nogc:

    int* destructions;
    bool armed;

    @disable this(this);

    ~this()
    {
        if (armed)
        {
            ++*destructions;
            armed = false;
        }
    }
}

/// An optional BetterC value. Option.init is absent.
///
/// Option owns cleanup of its active payload. `deinit`, `reset`, assignment to
/// `none`, and replacement all deinitialize a present value. `take`, `unwrap`,
/// and `expect` transfer the value out without cleaning it.
@mustuse struct Option(T)
{
nothrow @nogc:

    static assert(!is(T == void), "Option value type cannot be void");

    private bool present_;
    align(T.alignof) private ubyte[T.sizeof] storage_;

    // A cleanup-bearing payload must never acquire implicit owner copying just
    // because its representation happens to be copyable.
    static if (!__traits(isCopyable, T) || needsDeinit!T ||
        hasElaborateCopyConstructor!T)
        @disable this(this);

    /// Explicitly constructs an absent Option from `none()`.
    this(None)
    {
    }

    private ref inout(T) payload() inout return @system
    {
        return *cast(inout(T)*) storage_.ptr;
    }

    /// Replaces this Option by consuming `source`.
    ///
    /// Copyable, cleanup-free Options may also pass an lvalue here through the
    /// normal value copy into `source`. Cleanup-bearing Options require an
    /// rvalue/moved source because their copy constructor is disabled.
    ref Option opAssign(Option source) return
    {
        reset();
        if (source.present_)
        {
            moveEmplace(source.payload(), payload());
            source.present_ = false;
            present_ = true;
        }
        return this;
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
        moveEmplace(value, result.payload());
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
        return payload();
    }

    inout(T)* pointer() inout return @system
    {
        return present_ ? &payload() : null;
    }

    /// Explicitly ends this Option's lifetime.
    ///
    /// Only the active payload is cleaned. Absence owns nothing.
    void deinit()
    {
        if (!present_)
            return;

        static if (needsDeinit!T)
            deinitValue(payload());
        else static if (hasElaborateDestructor!T)
            destroy(payload());
        present_ = false;
    }

    /// Discards the current value, if any, and makes this Option absent and
    /// reusable.
    void reset()
    {
        deinit();
    }

    /// Transfers the current value out and leaves this Option absent.
    T take()
    {
        version (XTB_Checked)
            require(present_, "cannot take an empty Option");
        T result = void;
        moveEmplace(payload(), result);
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
        return payload();
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

/// Transforms a present simple value and preserves absence.
///
/// Owner-bearing payloads are deliberately rejected for now. This keeps the
/// chaining contract allocation-free and free of hidden ownership transfer.
auto map(alias transform, T, Args...)(
    Option!T option,
    auto ref Args args,
)
{
    static assert(isMonadicValue!T,
        "Option.map currently supports only payloads without deinit or D destructor semantics");
    alias U = typeof(transform(option.take(), forward!args));
    static assert(!is(U == void), "Option.map transform must return a value");
    static assert(isMonadicValue!U,
        "Option.map currently supports only result payloads without deinit or D destructor semantics");

    if (option.isNone)
        return Option!U.none();

    U value = transform(option.take(), forward!args);
    return Option!U.some(move(value));
}

/// Chains an Option-producing operation after a present simple Option.
auto andThen(alias transform, T, Args...)(
    Option!T option,
    auto ref Args args,
)
{
    static assert(isMonadicValue!T,
        "Option.andThen currently supports only payloads without deinit or D destructor semantics");
    alias Next = typeof(transform(option.take(), forward!args));
    static assert(
        isOptionType!Next,
        "Option.andThen transform must return Option",
    );
    static assert(isMonadicValue!(OptionValue!Next),
        "Option.andThen currently supports only result payloads without deinit or D destructor semantics");

    if (option.isNone)
        return Next.none();
    return transform(option.take(), forward!args);
}

/// Produces an alternate Option when this simple Option is absent.
auto orElse(alias transform, T, Args...)(
    Option!T option,
    auto ref Args args,
)
{
    static assert(isMonadicValue!T,
        "Option.orElse currently supports only payloads without deinit or D destructor semantics");
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
    import xtb.core.allocators.malloc : mallocAllocator;
    import xtb.core.string;

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

    int deinits;
    TrackedOptionValue first = TrackedOptionValue(&deinits, true);
    Option!TrackedOptionValue tracked = some(move(first));
    tracked.reset();
    assert(deinits == 1);

    TrackedOptionValue second = TrackedOptionValue(&deinits, true);
    tracked = some(move(second));
    TrackedOptionValue taken = tracked.take();
    assert(tracked.isNone);
    assert(deinits == 1);
    deinitValue(taken);
    assert(deinits == 2);

    int destructions;
    {
        DestructorOptionValue destructorValue =
            DestructorOptionValue(&destructions, true);
        Option!DestructorOptionValue destructorOption =
            some(move(destructorValue));
        destructorOption.reset();
        assert(destructions == 1);
    }
    assert(destructions == 1);
    static assert(!hasElaborateDestructor!(Option!DestructorOptionValue));

    static assert(!__traits(compiles,
            (ref Option!StringBuf value) { Option!StringBuf copy = value; }));
    static assert(!__traits(compiles,
            (ref Option!TrackedOptionValue value) { Option!TrackedOptionValue copy = value; }));

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

    static assert(!__traits(compiles, (Option!TrackedOptionValue value) {
        return value.map!(item => item);
    }));
}
