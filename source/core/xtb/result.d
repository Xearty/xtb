module xtb.result;

nothrow @nogc:

import core.attribute;
import core.internal.traits;
import d_lifetime = core.lifetime;

import xtb.lifetime;
import xtb.panic;
import xtb.types;

/// The active branch stored by a Result.
enum ResultState : u8
{
    ok,
    err,
}

private template is_copyable_result_value(T)
{
    static if (is(T == void))
    {
        enum bool is_copyable_result_value = true;
    }
    else
    {
        enum bool is_copyable_result_value = __traits(isCopyable, T)
            && !needs_deinit!T
            && !has_d_destructor!T
            && !hasElaborateCopyConstructor!T;
    }
}

private template is_monadic_value(T)
{
    static if (is(T == void))
    {
        enum bool is_monadic_value = true;
    }
    else
    {
        enum bool is_monadic_value = !needs_deinit!T
            && !has_d_destructor!T
            && !hasElaborateCopyConstructor!T;
    }
}

private enum bool is_result_type(T) = is(T == Result!(Value, Error), Value, Error);

private template ResultValue(T)
{
    static if (is(T == Result!(Value, Error), Value, Error))
        alias ResultValue = Value;
}

private template ResultError(T)
{
    static if (is(T == Result!(Value, Error), Value, Error))
        alias ResultError = Error;
}

/// An explicit success-or-error value for BetterC code.
///
/// A Result has exactly two logical states: `Ok(T)` and `Err(E)`. There is no
/// empty state. Default construction is disabled; construct through `ok` or
/// `err`.
///
/// `take`/`unwrap` and `take_error`/`unwrap_error` transfer the active payload
/// without cleaning it. The Result remains in the same logical branch with a
/// safely moved-from payload. Checked builds diagnose repeated semantic use of
/// a consumed Result; that diagnostic bit is not a third Result state. Both
/// branches must support context-free finalization because Result stores no
/// cleanup context.
///
/// `state`, `value_storage`, `error_storage`, and (in checked builds) `consumed`
/// expose the representation as required for XTB structs. Direct mutation must
/// preserve the active-branch and payload-lifetime invariants described above.
@mustuse struct Result(T, E)
{
nothrow @nogc:

    static assert(!is(E == void), "Result error type cannot be void");
    static if (!is(T == void))
    {
        static assert(
            can_finalize_without_context!T,
            "Result value type must support context-free finalization",
        );
    }
    static assert(
        can_finalize_without_context!E,
        "Result error type must support context-free finalization",
    );

    static if (is(T == void))
    {
        private enum bool value_needs_cleanup = false;
    }
    else
    {
        private enum bool value_needs_cleanup = needs_finalization!T;
    }
    private enum bool error_needs_cleanup = needs_finalization!E;
    private enum bool payload_needs_cleanup = value_needs_cleanup || error_needs_cleanup;

    ResultState state;
    static if (!is(T == void))
    {
        align(T.alignof) u8[T.sizeof] value_storage;
    }
    align(E.alignof) u8[E.sizeof] error_storage;
    version (XTB_Checked)
    {
        bool consumed;
    }

    @disable this();

    static if (!is_copyable_result_value!T || !is_copyable_result_value!E)
    {
        @disable this(this);
    }

    static if (!is(T == void))
    {
        private ref inout(T) value_payload() inout return @system
        {
            return *cast(inout(T)*) this.value_storage.ptr;
        }
    }

    private ref inout(E) error_payload() inout return @system
    {
        return *cast(inout(E)*) this.error_storage.ptr;
    }

    /// Replaces this Result by consuming `source`.
    ///
    /// Cleanup-bearing Results require an rvalue/moved source because implicit
    /// owner copying is disabled.
    ref Result opAssign(Result source) return
    {
        version (XTB_Checked)
        {
            require(!source.consumed, "cannot assign from a consumed Result");
        }

        static if (Result.payload_needs_cleanup)
            this.discard_active();

        this.state = source.state;
        static if (!is(T == void))
        {
            if (source.state == ResultState.ok)
            {
                move_emplace(source.value_payload(), this.value_payload());
            }
            else
            {
                move_emplace(source.error_payload(), this.error_payload());
            }
        }
        else
        {
            if (source.state == ResultState.err)
                move_emplace(source.error_payload(), this.error_payload());
        }
        version (XTB_Checked)
        {
            this.consumed = false;
            source.consumed = true;
        }
        return this;
    }

    static if (is(T == void))
    {
        static Result ok()
        {
            Result result = void;
            result.state = ResultState.ok;
            version (XTB_Checked)
            {
                result.consumed = false;
            }
            return result;
        }
    }
    else
    {
        static Result ok(T value)
        {
            Result result = void;
            move_emplace(value, result.value_payload());
            result.state = ResultState.ok;
            version (XTB_Checked)
            {
                result.consumed = false;
            }
            return result;
        }

        /// Constructs an ok Result by consuming an existing live payload.
        ///
        /// Package code uses this for semantic owners whose D destructor
        /// enforces an unresolved obligation, avoiding a by-value temporary.
        package(xtb) static Result ok_move(ref T value)
        {
            Result result = void;
            move_emplace(value, result.value_payload());
            result.state = ResultState.ok;
            version (XTB_Checked)
            {
                result.consumed = false;
            }
            return result;
        }
    }

    static Result err(E error)
    {
        Result result = void;
        move_emplace(error, result.error_payload());
        result.state = ResultState.err;
        version (XTB_Checked)
        {
            result.consumed = false;
        }
        return result;
    }

    /// Rebinds an error from another Result with the same error type.
    ///
    /// The source must currently be an error. Its error payload is transferred
    /// and the source remains `Err` with a moved-from payload.
    static Result err(U)(ref Result!(U, E) source)
    {
        return Result.err(source.take_error());
    }

    bool is_ok() const pure @safe
    {
        return this.state == ResultState.ok;
    }

    bool is_err() const pure @safe
    {
        return this.state == ResultState.err;
    }

    void pretty_describe(Pretty)(scope ref Pretty pretty) const
    {
        if (this.is_err)
        {
            pretty.constructor("err", this.error);
            return;
        }

        static if (is(T == void))
        {
            pretty.constructor("ok");
        }
        else
        {
            pretty.constructor("ok", this.value);
        }
    }

    /// Converts to true exactly when this Result is successful.
    bool opCast(U : bool)() const pure @safe
    {
        return this.is_ok;
    }

    private void discard_active()
    {
        if (this.state == ResultState.ok)
        {
            static if (!is(T == void))
            {
                static if (Result.value_needs_cleanup)
                    finalize(this.value_payload());
            }
        }
        else
        {
            static if (Result.error_needs_cleanup)
                finalize(this.error_payload());
        }
    }

    static if (Result.payload_needs_cleanup)
    {
        /// Explicitly ends this Result's lifetime by cleaning only its active
        /// branch. A moved-from active payload is safe to deinitialize.
        void deinit()
        {
            this.discard_active();
        }
    }

    static if (!is(T == void))
    {
        ref inout(T) value() inout return @system
        {
            version (XTB_Checked)
            {
                require(!this.consumed, "consumed Result has no usable value");
            }
            require(this.is_ok, "result does not contain a value");
            return this.value_payload();
        }

        /// Transfers the success value out. The Result stays logically `Ok`
        /// with a moved-from payload.
        T take()
        {
            version (XTB_Checked)
            {
                require(!this.consumed, "cannot take from a consumed Result");
            }
            require(this.is_ok, "cannot take the value of a non-ok Result");

            T result = void;
            move_emplace(this.value_payload(), result);
            version (XTB_Checked)
            {
                this.consumed = true;
            }
            return result;
        }

        /// Transfers the success value out or panics unless this Result is ok.
        T unwrap()
        {
            version (XTB_Checked)
            {
                if (this.consumed)
                    panic("cannot unwrap a consumed Result");
            }
            if (!this.is_ok)
                panic("cannot unwrap an error Result");

            return this.take();
        }

        /// Transfers the success value out or panics with `message` unless ok.
        T expect(String message)
        {
            version (XTB_Checked)
            {
                if (this.consumed)
                    panic(message);
            }
            if (!this.is_ok)
                panic(message);

            return this.take();
        }
    }
    else
    {
        /// Consumes the successful void branch while preserving the logical
        /// `Ok` state.
        void take()
        {
            version (XTB_Checked)
            {
                require(!this.consumed, "cannot take from a consumed Result");
            }
            require(this.is_ok, "cannot take the value of a non-ok Result");
            version (XTB_Checked)
            {
                this.consumed = true;
            }
        }

        /// Consumes this Result or panics unless it is ok.
        void unwrap()
        {
            version (XTB_Checked)
            {
                if (this.consumed)
                    panic("cannot unwrap a consumed Result");
            }
            if (!this.is_ok)
                panic("cannot unwrap an error Result");

            this.take();
        }

        /// Consumes this Result or panics with `message` unless it is ok.
        void expect(String message)
        {
            version (XTB_Checked)
            {
                if (this.consumed)
                    panic(message);
            }
            if (!this.is_ok)
                panic(message);

            this.take();
        }
    }

    ref inout(E) error() inout return @system
    {
        version (XTB_Checked)
        {
            require(!this.consumed, "consumed Result has no usable error");
        }
        require(this.is_err, "result does not contain an error");
        return this.error_payload();
    }

    /// Transfers the error out. The Result stays logically `Err` with a
    /// moved-from payload.
    E take_error()
    {
        version (XTB_Checked)
        {
            require(!this.consumed, "cannot take from a consumed Result");
        }
        require(this.is_err, "cannot take the error of a non-error Result");

        E result = void;
        move_emplace(this.error_payload(), result);
        version (XTB_Checked)
        {
            this.consumed = true;
        }
        return result;
    }

    /// Transfers the error out or panics unless this Result is an error.
    E unwrap_error()
    {
        version (XTB_Checked)
        {
            if (this.consumed)
                panic("cannot unwrap the error of a consumed Result");
        }
        if (!this.is_err)
            panic("cannot unwrap the error of an ok Result");

        return this.take_error();
    }

    /// Transfers the error out or panics with `message` unless this Result is an error.
    E expect_error(String message)
    {
        version (XTB_Checked)
        {
            if (this.consumed)
                panic(message);
        }
        if (!this.is_err)
            panic(message);

        return this.take_error();
    }
}

/// Introduces `ok` and `err` aliases for the enclosing function's Result type.
mixin template ResultReturns()
{
    alias ok = typeof(return).ok;
    alias err = typeof(return).err;
}

/// Transforms a simple success value while preserving a simple error type.
auto map(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    static assert(
        is_monadic_value!T && is_monadic_value!E,
        "Result.map currently supports only payloads without deinit or D destructor semantics",
    );

    static if (is(T == void))
    {
        alias U = typeof(transform(d_lifetime.forward!args));
    }
    else
    {
        alias U = typeof(transform(result.take(), d_lifetime.forward!args));
    }
    static assert(
        is_monadic_value!U,
        "Result.map currently supports only result payloads without deinit or D "
            ~ "destructor semantics",
    );

    alias Mapped = Result!(U, E);
    if (result.is_err)
        return Mapped.err(result.take_error());

    static if (is(T == void))
    {
        result.take();
        static if (is(U == void))
        {
            transform(d_lifetime.forward!args);
            return Mapped.ok();
        }
        else
        {
            U value = transform(d_lifetime.forward!args);
            return Mapped.ok(move(value));
        }
    }
    else
    {
        static if (is(U == void))
        {
            transform(result.take(), d_lifetime.forward!args);
            return Mapped.ok();
        }
        else
        {
            U value = transform(result.take(), d_lifetime.forward!args);
            return Mapped.ok(move(value));
        }
    }
}

/// Transforms a simple error while preserving a simple success type.
auto map_error(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    static assert(
        is_monadic_value!T && is_monadic_value!E,
        "Result.map_error currently supports only payloads without deinit or D "
            ~ "destructor semantics",
    );
    alias F = typeof(transform(result.take_error(), d_lifetime.forward!args));
    static assert(!is(F == void), "Result.map_error transform must return an error value");
    static assert(
        is_monadic_value!F,
        "Result.map_error currently supports only result payloads without deinit or D "
            ~ "destructor semantics",
    );
    alias Mapped = Result!(T, F);

    if (result.is_err)
    {
        F error = transform(result.take_error(), d_lifetime.forward!args);
        return Mapped.err(move(error));
    }

    static if (is(T == void))
    {
        result.take();
        return Mapped.ok();
    }
    else
    {
        return Mapped.ok(result.take());
    }
}

/// Chains a Result-producing operation after a successful simple Result.
auto and_then(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    static assert(
        is_monadic_value!T && is_monadic_value!E,
        "Result.and_then currently supports only payloads without deinit or D destructor semantics",
    );

    static if (is(T == void))
    {
        alias Next = typeof(transform(d_lifetime.forward!args));
    }
    else
    {
        alias Next = typeof(transform(result.take(), d_lifetime.forward!args));
    }

    static assert(is_result_type!Next, "Result.and_then transform must return Result");
    static assert(
        is(ResultError!Next == E),
        "Result.and_then transform must preserve the error type; use map_error to convert errors",
    );
    static assert(
        is_monadic_value!(ResultValue!Next) && is_monadic_value!(ResultError!Next),
        "Result.and_then currently supports only result payloads without deinit or D "
            ~ "destructor semantics",
    );

    if (result.is_err)
        return Next.err(result.take_error());

    static if (is(T == void))
    {
        result.take();
        return transform(d_lifetime.forward!args);
    }
    else
    {
        return transform(result.take(), d_lifetime.forward!args);
    }
}

/// Recovers from a simple error with another simple Result-producing operation.
auto or_else(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    static assert(
        is_monadic_value!T && is_monadic_value!E,
        "Result.or_else currently supports only payloads without deinit or D destructor semantics",
    );
    alias Next = typeof(transform(result.take_error(), d_lifetime.forward!args));
    static assert(is_result_type!Next, "Result.or_else transform must return Result");
    static assert(
        is(ResultValue!Next == T),
        "Result.or_else transform must preserve the success type; use map to convert values",
    );
    static assert(
        is_monadic_value!(ResultValue!Next) && is_monadic_value!(ResultError!Next),
        "Result.or_else currently supports only result payloads without deinit or D "
            ~ "destructor semantics",
    );

    if (result.is_err)
        return transform(result.take_error(), d_lifetime.forward!args);

    static if (is(T == void))
    {
        result.take();
        return Next.ok();
    }
    else
    {
        return Next.ok(result.take());
    }
}

version (unittest)
{
    private struct TrackedResultValue
    {
    nothrow @nogc:

        i32* deinits;
        i32 value;
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

    private struct DestructorResultValue
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

    private enum ResultTestError
    {
        first,
        second,
    }

    private Result!(i32, ResultTestError) result_test_source(bool fail)
    {
        mixin ResultReturns;
        if (fail) return err(ResultTestError.first);
        return ok(20);
    }

    private Result!(i64, ResultTestError) result_test_propagate(bool fail)
    {
        mixin ResultReturns;
        auto source = result_test_source(fail);
        if (!source) return err(source);
        return ok(source.take() + 2L);
    }
}

unittest
{
    static assert(!__traits(
        compiles,
        ()
        {
            Result!(i32, ResultTestError) value;
        },
    ));

    auto success = Result!(i32, ResultTestError).ok(42);
    assert(success.is_ok && !success.is_err);
    assert(success);
    assert(success.value == 42);
    success.value += 1;
    assert(success.unwrap() == 43);
    assert(success.is_ok);

    auto expected_success = Result!(i32, ResultTestError).ok(44);
    assert(expected_success.expect("expected success") == 44);
    assert(expected_success.is_ok);

    auto failure = Result!(i32, ResultTestError).err(ResultTestError.second);
    assert(!failure);
    assert(failure.is_err && failure.error == ResultTestError.second);
    assert(failure.unwrap_error() == ResultTestError.second);
    assert(failure.is_err);

    auto expected_failure = Result!(i32, ResultTestError).err(ResultTestError.first);
    assert(expected_failure.expect_error("expected error") == ResultTestError.first);
    assert(expected_failure.is_err);

    auto propagated_success = result_test_propagate(false);
    assert(propagated_success && propagated_success.value == 22);

    auto propagated_failure = result_test_propagate(true);
    assert(!propagated_failure && propagated_failure.error == ResultTestError.first);

    const const_success = Result!(i32, ResultTestError).ok(7);
    static assert(is(typeof(const_success.value()) == const(i32)));
    assert(const_success.value == 7);

    immutable immutable_success = Result!(i32, ResultTestError).ok(9);
    static assert(is(typeof(immutable_success.value()) == immutable(i32)));
    assert(immutable_success.value == 9);
}

unittest
{
    auto mapped = result_test_source(false).map!(value => value * 2);
    assert(mapped && mapped.value == 40);

    auto mapped_failure = result_test_source(true).map!(value => value * 2);
    assert(mapped_failure.is_err && mapped_failure.error == ResultTestError.first);

    auto mapped_error = result_test_source(true).map_error!(error => cast(i32) error + 10);
    static assert(is(typeof(mapped_error) == Result!(i32, i32)));
    assert(mapped_error.is_err && mapped_error.error == 10);

    auto chained = result_test_source(false).and_then!(
        value => Result!(i64, ResultTestError).ok(value + 5L),
    );
    assert(chained && chained.value == 25L);

    i32 offset = 3;
    auto captured = result_test_source(false).map!(value => value + offset);
    assert(captured && captured.value == 23);

    auto recovered = result_test_source(true).or_else!(
        error => Result!(i32, i32).ok(error == ResultTestError.first ? 99 : 0),
    );
    static assert(is(typeof(recovered) == Result!(i32, i32)));
    assert(recovered && recovered.value == 99);
}

unittest
{
    alias VoidResult = Result!(void, ResultTestError);

    auto success = VoidResult.ok();
    assert(success);
    success.unwrap();
    assert(success.is_ok);

    auto expected_success = VoidResult.ok();
    expected_success.expect("expected void success");
    assert(expected_success.is_ok);

    i32 calls;
    success = VoidResult.ok();
    auto mapped = move(success).map!(
        ()
        {
            ++calls;
            return 5;
        },
    );
    assert(mapped && mapped.value == 5 && calls == 1);

    auto chained = VoidResult.ok().and_then!(
        () => Result!(i32, ResultTestError).ok(8),
    );
    assert(chained && chained.value == 8);

    auto failure = VoidResult.err(ResultTestError.second);
    auto untouched = move(failure).map!(
        ()
        {
            ++calls;
        },
    );
    static assert(is(typeof(untouched) == VoidResult));
    assert(untouched.is_err && untouched.error == ResultTestError.second);
    assert(calls == 1);
}

unittest
{
    i32 deinits;
    auto source = TrackedResultValue(&deinits, 7, true);
    auto result = Result!(TrackedResultValue, ResultTestError).ok(move(source));
    assert(result.value.value == 7);

    TrackedResultValue extracted = result.take();
    assert(result.is_ok);
    assert(deinits == 0);
    xtb.lifetime.deinit(result);
    assert(deinits == 0);
    xtb.lifetime.deinit(extracted);
    assert(deinits == 1);

    auto replacement_value = TrackedResultValue(&deinits, 8, true);
    auto replacement = Result!(TrackedResultValue, ResultTestError).ok(move(replacement_value));
    auto old_value = TrackedResultValue(&deinits, 9, true);
    auto target = Result!(TrackedResultValue, ResultTestError).ok(move(old_value));
    target = move(replacement);
    assert(deinits == 2);
    assert(target.value.value == 8);
    xtb.lifetime.deinit(target);
    assert(deinits == 3);

    static assert(!__traits(
        compiles,
        (ref Result!(TrackedResultValue, ResultTestError) value)
        {
            Result!(TrackedResultValue, ResultTestError) copy = value;
        },
    ));
    static assert(!__traits(
        compiles,
        (Result!(TrackedResultValue, ResultTestError) value)
        {
            return value.map!(item => item.value);
        },
    ));
}

unittest
{
    static assert(!hasElaborateDestructor!(Result!(DestructorResultValue, ResultTestError)));
    static assert(!hasElaborateDestructor!(Result!(i32, DestructorResultValue)));

    i32 destructions;
    auto success_value = DestructorResultValue(&destructions, true);
    auto success = Result!(DestructorResultValue, ResultTestError).ok(move(success_value));
    xtb.lifetime.deinit(success);
    assert(destructions == 1);

    auto error_value = DestructorResultValue(&destructions, true);
    auto failure = Result!(i32, DestructorResultValue).err(move(error_value));
    xtb.lifetime.deinit(failure);
    assert(destructions == 2);

    auto transferred_value = DestructorResultValue(&destructions, true);
    auto transferred = Result!(DestructorResultValue, ResultTestError).ok(move(transferred_value));
    DestructorResultValue extracted = transferred.take();
    xtb.lifetime.deinit(transferred);
    assert(destructions == 2);
    destroy(extracted);
    assert(destructions == 3);
}
