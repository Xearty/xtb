module xtb.option;

nothrow @nogc:

import core.attribute;
import core.internal.traits;
import d_lifetime = core.lifetime;

import xtb.lifetime;
import xtb.panic;
import xtb.types;

private enum bool is_option_type(T) = is(T == Option!Value, Value);

private template OptionValue(T)
{
    static if (is(T == Option!Value, Value))
        alias OptionValue = Value;
}

private enum bool is_monadic_value(T) = !needs_deinit!T
    && !has_d_destructor!T
    && !hasElaborateCopyConstructor!T;

/// Explicit absence token accepted by Option construction and assignment.
struct None
{
}

/// An optional BetterC value. Option.init is absent.
///
/// Option owns cleanup of its active payload. Cleanup-bearing instantiations
/// expose `deinit`; `reset`, assignment to `none`, and replacement are always
/// available and discard a present value. `take`, `unwrap`, and `expect`
/// transfer the value out without cleaning it. Payloads must support
/// context-free finalization because Option stores no cleanup context.
///
/// `present` and `storage` expose the representation as required for XTB
/// structs. Callers that mutate them directly must preserve the invariant that
/// `present == true` means `storage` contains exactly one live `T` object.
@mustuse struct Option(T)
{
nothrow @nogc:

    static assert(!is(T == void), "Option value type cannot be void");
    static assert(
        can_finalize_without_context!T,
        "Option payload must support context-free finalization",
    );

    private enum bool payload_needs_cleanup = needs_finalization!T;

    bool present;
    align(T.alignof) u8[T.sizeof] storage;

    // A cleanup-bearing payload must never acquire implicit owner copying just
    // because its representation happens to be copyable.
    static if (
        !__traits(isCopyable, T)
        || needs_deinit!T
        || has_d_destructor!T
        || hasElaborateCopyConstructor!T
    )
    {
        @disable this(this);
    }

    /// Explicitly constructs an absent Option from `none()`.
    this(None)
    {
    }

    /// Replaces this Option by consuming `source`.
    ///
    /// Copyable, cleanup-free Options may also pass an lvalue here through the
    /// normal value copy into `source`. Cleanup-bearing Options require an
    /// rvalue/moved source because their copy constructor is disabled.
    ref Option opAssign(Option source) return
    {
        this.reset();
        if (source.present)
        {
            move_emplace(source.payload(), this.payload());
            source.present = false;
            this.present = true;
        }
        return this;
    }

    /// Explicitly clears this Option through `option = none()`.
    ref Option opAssign(None) return
    {
        this.reset();
        return this;
    }

    static Option none()
    {
        return Option.init;
    }

    static Option some(T value)
    {
        Option result;
        move_emplace(value, result.payload());
        result.present = true;
        return result;
    }

    bool is_some() const pure @safe
    {
        return this.present;
    }

    bool is_none() const pure @safe
    {
        return !this.present;
    }

    /// Converts to true exactly when this Option contains a value.
    bool opCast(U : bool)() const pure @safe
    {
        return this.is_some;
    }

    /// This function exists only for compatibility with range-oriented generic
    /// code. Use `is_none` when directly inspecting an `Option`.
    bool empty() const pure @safe
    {
        return this.is_none;
    }

    ref inout(T) value() inout return @system
    {
        require(this.present, "empty Option has no value");
        return this.payload();
    }

    void prettyDescribe(Pretty)(scope ref Pretty pretty) const
    {
        if (this.is_none)
        {
            pretty.atom("none", pretty.nullRole);
            return;
        }
        pretty.constructor("some", this.value);
    }

    inout(T)* pointer() inout return @system
    {
        return this.present ? &this.payload() : null;
    }

    static if (Option.payload_needs_cleanup)
    {
        /// Explicitly ends this cleanup-bearing Option's lifetime.
        ///
        /// Only the active payload is cleaned. Absence owns nothing.
        void deinit()
        {
            this.discard_active();
        }
    }

    /// Discards the current value, if any, and makes this Option absent and
    /// reusable.
    void reset()
    {
        this.discard_active();
    }

    /// Transfers the current value out and leaves this Option absent.
    T take()
    {
        require(this.present, "cannot take an empty Option");
        T result = void;
        move_emplace(this.payload(), result);
        this.present = false;
        return result;
    }

    /// Transfers the value out or panics when this Option is absent.
    ///
    /// Unlike checked contracts, this state check is always enabled.
    T unwrap()
    {
        if (!this.present)
            panic("cannot unwrap an empty Option");

        return this.take();
    }

    /// Transfers the value out or panics with `message` when absent.
    ///
    /// Unlike checked contracts, this state check is always enabled.
    T expect(String message)
    {
        if (!this.present)
            panic(message);

        return this.take();
    }

    private ref inout(T) payload() inout return @system
    {
        return *cast(inout(T)*) this.storage.ptr;
    }

    package(xtb) ref T payload_storage() return @system
    {
        return this.payload();
    }

    package(xtb) void mark_present()
    {
        this.present = true;
    }

    private void discard_active()
    {
        if (!this.present)
            return;

        static if (Option.payload_needs_cleanup)
            finalize(this.payload());

        this.present = false;
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
    static assert(
        is_monadic_value!T,
        "Option.map currently supports only payloads without deinit or D destructor semantics",
    );
    alias U = typeof(transform(option.take(), d_lifetime.forward!args));
    static assert(!is(U == void), "Option.map transform must return a value");
    static assert(
        is_monadic_value!U,
        "Option.map currently supports only result payloads without deinit or D "
            ~ "destructor semantics",
    );

    if (option.is_none)
        return Option!U.none();

    U value = transform(option.take(), d_lifetime.forward!args);
    return Option!U.some(move(value));
}

/// Chains an Option-producing operation after a present simple Option.
auto and_then(alias transform, T, Args...)(
    Option!T option,
    auto ref Args args,
)
{
    static assert(
        is_monadic_value!T,
        "Option.and_then currently supports only payloads without deinit or D destructor semantics",
    );
    alias Next = typeof(transform(option.take(), d_lifetime.forward!args));
    static assert(
        is_option_type!Next,
        "Option.and_then transform must return Option",
    );
    static assert(
        is_monadic_value!(OptionValue!Next),
        "Option.and_then currently supports only result payloads without deinit or D "
            ~ "destructor semantics",
    );

    if (option.is_none)
        return Next.none();

    return transform(option.take(), d_lifetime.forward!args);
}

/// Produces an alternate Option when this simple Option is absent.
auto or_else(alias transform, T, Args...)(
    Option!T option,
    auto ref Args args,
)
{
    static assert(
        is_monadic_value!T,
        "Option.or_else currently supports only payloads without deinit or D destructor semantics",
    );
    alias Next = typeof(transform(d_lifetime.forward!args));
    static assert(
        is(Next == Option!T),
        "Option.or_else transform must return the same Option type",
    );

    if (option.is_none)
        return transform(d_lifetime.forward!args);

    return Next.some(option.take());
}

version (unittest)
{
    import xtb.allocators.malloc;
    import xtb.string;

    private struct TrackedOptionValue
    {
    nothrow @nogc:

        i32* deinits;
        bool armed;

        @disable this(this);

        void deinit()
        {
            if (this.armed)
            {
                ++*this.deinits;
                this.armed = false;
            }
        }
    }

    private struct DestructorOptionValue
    {
    nothrow @nogc:

        i32* destructions;
        bool armed;

        @disable this(this);

        ~this()
        {
            if (this.armed)
            {
                ++*this.destructions;
                this.armed = false;
            }
        }
    }

    private Option!i32 option_test_return(bool present)
    {
        mixin OptionReturns;
        if (!present) return none();
        return some(12);
    }
}

unittest
{
    static assert(!__traits(compiles, Option!i32(13)));
    static assert(!__traits(compiles, ()
    {
        Option!i32 value = 13;
    }));
    static assert(!__traits(compiles, ()
    {
        Option!i32 value;
        value = 13;
    }));

    Option!i32 number;
    assert(number.is_none && number.empty);
    assert(!number);
    assert(number.pointer is null);

    number = some(42);
    assert(number.is_some && number);
    assert(number.value == 42);
    assert(number.pointer is &number.value());

    assert(number.take == 42);
    assert(number.is_none);
    assert(number.pointer is null);

    number = some(51);
    assert(number.unwrap() == 51);
    assert(number.is_none);

    number = some(52);
    assert(number.expect("expected a number") == 52);
    assert(number.is_none);
}

unittest
{
    Option!i32 declared_some = some(13);
    Option!i32 declared_none = none();
    assert(declared_some.is_some && declared_some.value == 13);
    assert(declared_none.is_none);

    declared_some = none();
    declared_none = some(17);
    assert(declared_some.is_none);
    assert(declared_none.is_some && declared_none.value == 17);

    Option!i32 copied = some(7);
    Option!i32 copied_again = copied;
    copied = some(9);
    assert(copied.value == 9);
    assert(copied_again.value == 7);

    copied.reset();
    assert(copied.is_none);
}

unittest
{
    const Option!i32 read_only = some(5);
    static assert(is(typeof(read_only.value()) == const(i32)));
    static assert(is(typeof(read_only.pointer()) == const(i32)*));

    immutable Option!i32 immutable_value = Option!i32.some(6);
    static assert(is(typeof(immutable_value.value()) == immutable(i32)));
    static assert(is(typeof(immutable_value.pointer()) == immutable(i32)*));
}

unittest
{
    assert(option_test_return(false).is_none);
    assert(option_test_return(true).value == 12);
}

unittest
{
    StringBuf source = StringBuf.fromString(mallocAllocator(), "owned");
    Option!StringBuf text = some(move(source));
    assert(source.allocator is null);
    assert(text.value == "owned");

    text.value.append(" value");
    StringBuf extracted = text.unwrap();
    assert(text.is_none);
    assert(extracted == "owned value");

    text = some(move(extracted));
    text.reset();
    assert(text.is_none);
}

unittest
{
    i32 deinits;
    TrackedOptionValue first = TrackedOptionValue(&deinits, true);
    Option!TrackedOptionValue tracked = some(move(first));

    tracked.reset();
    assert(deinits == 1);

    TrackedOptionValue second = TrackedOptionValue(&deinits, true);
    tracked = some(move(second));
    TrackedOptionValue taken = tracked.take();
    assert(tracked.is_none);
    assert(deinits == 1);

    xtb.lifetime.deinit(taken);
    assert(deinits == 2);
}

unittest
{
    i32 destructions;
    {
        DestructorOptionValue destructor_value =
            DestructorOptionValue(&destructions, true);
        Option!DestructorOptionValue destructor_option = some(move(destructor_value));

        destructor_option.reset();
        assert(destructions == 1);
    }

    assert(destructions == 1);
    static assert(!hasElaborateDestructor!(Option!DestructorOptionValue));
}

unittest
{
    static assert(!__traits(compiles,
        (ref Option!StringBuf value)
        {
            Option!StringBuf copy = value;
        }));
    static assert(!__traits(compiles,
        (ref Option!TrackedOptionValue value)
        {
            Option!TrackedOptionValue copy = value;
        }));
}

unittest
{
    Option!(i32*) present_null = some(cast(i32*) null);
    assert(present_null.is_some && present_null.value is null);

    present_null = none();
    assert(present_null.is_none);
}

unittest
{
    auto mapped = some(4).map!(value => value * 3);
    assert(mapped.is_some && mapped.value == 12);
    assert(Option!i32.none().map!(value => value * 3).is_none);

    auto chained = some(4).and_then!(
        value => value > 0 ? some(value + 1) : Option!i32.none(),
    );
    assert(chained.is_some && chained.value == 5);

    i32 fallback_calls;
    auto retained = some(4).or_else!(
        ()
        {
            ++fallback_calls;
            return some(9);
        },
    );
    assert(retained.value == 4 && fallback_calls == 0);

    auto recovered = Option!i32.none().or_else!(
        ()
        {
            ++fallback_calls;
            return some(9);
        },
    );
    assert(recovered.value == 9 && fallback_calls == 1);

    i32 offset = 10;
    auto captured = some(2).map!(value => value + offset);
    assert(captured.value == 12);

    static assert(!__traits(compiles,
        (Option!TrackedOptionValue value)
        {
            return value.map!(item => item);
        }));
}
