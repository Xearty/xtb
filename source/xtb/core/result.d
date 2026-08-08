module xtb.core.result;

nothrow @nogc:

import core.attribute : mustuse;
import core.lifetime : forward, move, moveEmplace;
version (XTB_Checked)
    import xtb.core.panic : require;

private enum ResultState : ubyte
{
    empty,
    ok,
    err,
}

private template IsCopyableResultValue(T)
{
    static if (is(T == void))
        enum bool IsCopyableResultValue = true;
    else
        enum bool IsCopyableResultValue = __traits(isCopyable, T);
}

private enum bool isResultType(T) = is(T == Result!(Value, Error), Value, Error);
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
/// `Result.init` is an empty, valid value. `take` and `takeError` leave the
/// result empty after transferring the active payload out. Use `ok`/`err` to
/// construct a populated result and `ResultReturns` inside Result-returning
/// functions for concise `return ok(...)` / `return err(...)` syntax.
@mustuse struct Result(T, E)
{
nothrow @nogc:

    static assert(!is(E == void), "Result error type cannot be void");

    private ResultState state_;
    static if (!is(T == void))
        private T value_;
    private E error_;

    static if (!IsCopyableResultValue!T || !__traits(isCopyable, E))
        @disable this(this);

    static if (is(T == void))
    {
        static Result ok()
        {
            Result result;
            result.state_ = ResultState.ok;
            return result;
        }
    }
    else
    {
        static Result ok(T value)
        {
            Result result;
            move(value, result.value_);
            result.state_ = ResultState.ok;
            return result;
        }
    }

    static Result err(E error)
    {
        Result result;
        move(error, result.error_);
        result.state_ = ResultState.err;
        return result;
    }

    /// Rebind an error from another Result with the same error type.
    ///
    /// The source must currently be an error and is left empty. This overload
    /// exists primarily for `return err(otherResult)` through ResultReturns.
    static Result err(U)(ref Result!(U, E) source)
    {
        return err(source.takeError());
    }

    bool isOk() const pure @safe
    {
        return state_ == ResultState.ok;
    }

    bool isErr() const pure @safe
    {
        return state_ == ResultState.err;
    }

    /// True for Result.init and after its active payload has been taken.
    bool isEmpty() const pure @safe
    {
        return state_ == ResultState.empty;
    }

    /// Converts to true exactly when this Result is successful.
    bool opCast(U : bool)() const pure @safe
    {
        return isOk;
    }

    static if (!is(T == void))
    {
        ref inout(T) value() inout return @system
        {
            version (XTB_Checked)
                require(isOk, "Result does not contain a value");
            return value_;
        }

        /// Transfers the success value out and leaves this Result empty.
        T take()
        {
            version (XTB_Checked)
                require(isOk, "cannot take the value of a non-ok Result");
            T result = void;
            moveEmplace(value_, result);
            static if (__traits(isPOD, T))
                value_ = T.init;
            state_ = ResultState.empty;
            return result;
        }
    }
    else
    {
        /// Consumes a successful void Result and leaves it empty.
        void take()
        {
            version (XTB_Checked)
                require(isOk, "cannot take the value of a non-ok Result");
            state_ = ResultState.empty;
        }
    }

    ref inout(E) error() inout return @system
    {
        version (XTB_Checked)
            require(isErr, "Result does not contain an error");
        return error_;
    }

    /// Transfers the error out and leaves this Result empty.
    E takeError()
    {
        version (XTB_Checked)
            require(isErr, "cannot take the error of a non-error Result");
        E result = void;
        moveEmplace(error_, result);
        static if (__traits(isPOD, E))
            error_ = E.init;
        state_ = ResultState.empty;
        return result;
    }
}

/// Introduces `ok` and `err` aliases for the enclosing function's Result type.
///
/// Example:
/// ---
/// Result!(Config, Error) loadConfig()
/// {
///     mixin ResultReturns;
///     if (failed)
///         return err(Error.invalid);
///     return ok(config);
/// }
/// ---
mixin template ResultReturns()
{
    alias ok = typeof(return).ok;
    alias err = typeof(return).err;
}

/// Transforms the success value while preserving the error type.
auto map(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    static if (is(T == void))
        alias U = typeof(transform(forward!args));
    else
        alias U = typeof(transform(result.take(), forward!args));

    alias Mapped = Result!(U, E);
    if (result.isErr)
        return Mapped.err(result.takeError());

    version (XTB_Checked)
        require(result.isOk, "cannot map an empty Result");

    static if (is(T == void))
    {
        result.take();
        static if (is(U == void))
        {
            transform(forward!args);
            return Mapped.ok();
        }
        else
        {
            U value = transform(forward!args);
            return Mapped.ok(move(value));
        }
    }
    else
    {
        static if (is(U == void))
        {
            transform(result.take(), forward!args);
            return Mapped.ok();
        }
        else
        {
            U value = transform(result.take(), forward!args);
            return Mapped.ok(move(value));
        }
    }
}

/// Transforms the error while preserving the success type.
auto mapError(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    alias F = typeof(transform(result.takeError(), forward!args));
    static assert(!is(F == void), "Result.mapError transform must return an error value");
    alias Mapped = Result!(T, F);

    if (result.isErr)
    {
        F error = transform(result.takeError(), forward!args);
        return Mapped.err(move(error));
    }

    version (XTB_Checked)
        require(result.isOk, "cannot map an empty Result");

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

/// Chains a Result-producing operation after a successful Result.
auto andThen(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    static if (is(T == void))
        alias Next = typeof(transform(forward!args));
    else
        alias Next = typeof(transform(result.take(), forward!args));

    static assert(
        isResultType!Next,
        "Result.andThen transform must return Result",
    );
    static assert(
        is(ResultError!Next == E),
        "Result.andThen transform must preserve the error type; use mapError to convert errors",
    );

    if (result.isErr)
        return Next.err(result.takeError());

    version (XTB_Checked)
        require(result.isOk, "cannot chain an empty Result");

    static if (is(T == void))
    {
        result.take();
        return transform(forward!args);
    }
    else
    {
        return transform(result.take(), forward!args);
    }
}

/// Recovers from an error with another Result-producing operation.
auto orElse(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    alias Next = typeof(transform(result.takeError(), forward!args));
    static assert(
        isResultType!Next,
        "Result.orElse transform must return Result",
    );
    static assert(
        is(ResultValue!Next == T),
        "Result.orElse transform must preserve the success type; use map to convert values",
    );

    if (result.isErr)
        return transform(result.takeError(), forward!args);

    version (XTB_Checked)
        require(result.isOk, "cannot recover an empty Result");

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

version (unittest) private struct TrackedResultValue
{
nothrow @nogc:

    int* destructions;
    int value;
    bool armed;

    @disable this(this);

    ~this()
    {
        if (armed)
            ++*destructions;
    }
}

version (unittest) private enum ResultTestError
{
    first,
    second,
}

version (unittest) private Result!(int, ResultTestError) resultTestSource(bool fail)
{
    mixin ResultReturns;
    if (fail)
        return err(ResultTestError.first);
    return ok(20);
}

version (unittest) private Result!(long, ResultTestError) resultTestPropagate(bool fail)
{
    mixin ResultReturns;
    auto source = resultTestSource(fail);
    if (!source)
        return err(source);
    return ok(source.take() + 2L);
}

unittest
{
    Result!(int, ResultTestError) empty;
    assert(empty.isEmpty);
    assert(!empty.isOk && !empty.isErr);
    assert(!cast(bool) empty);

    auto success = Result!(int, ResultTestError).ok(42);
    assert(success.isOk && !success.isErr && !success.isEmpty);
    assert(success);
    assert(success.value == 42);
    success.value += 1;
    assert(success.take() == 43);
    assert(success.isEmpty);

    auto failure = Result!(int, ResultTestError).err(ResultTestError.second);
    assert(!failure);
    assert(failure.isErr && failure.error == ResultTestError.second);
    assert(failure.takeError() == ResultTestError.second);
    assert(failure.isEmpty);

    auto propagatedSuccess = resultTestPropagate(false);
    assert(propagatedSuccess && propagatedSuccess.value == 22);
    auto propagatedFailure = resultTestPropagate(true);
    assert(!propagatedFailure && propagatedFailure.error == ResultTestError.first);

    const constSuccess = Result!(int, ResultTestError).ok(7);
    static assert(is(typeof(constSuccess.value()) == const(int)));
    assert(constSuccess.value == 7);

    immutable immutableSuccess = Result!(int, ResultTestError).ok(9);
    static assert(is(typeof(immutableSuccess.value()) == immutable(int)));
    assert(immutableSuccess.value == 9);
}

unittest
{
    auto mapped = resultTestSource(false).map!(value => value * 2);
    assert(mapped && mapped.value == 40);

    auto mappedFailure = resultTestSource(true).map!(value => value * 2);
    assert(mappedFailure.isErr && mappedFailure.error == ResultTestError.first);

    auto mappedError = resultTestSource(true).mapError!(error => cast(int) error + 10);
    static assert(is(typeof(mappedError) == Result!(int, int)));
    assert(mappedError.isErr && mappedError.error == 10);

    auto chained = resultTestSource(false).andThen!(value =>
        Result!(long, ResultTestError).ok(value + 5L));
    assert(chained && chained.value == 25L);

    int offset = 3;
    auto captured = resultTestSource(false).map!(value => value + offset);
    assert(captured && captured.value == 23);

    auto recovered = resultTestSource(true).orElse!(error =>
        Result!(int, int).ok(error == ResultTestError.first ? 99 : 0));
    static assert(is(typeof(recovered) == Result!(int, int)));
    assert(recovered && recovered.value == 99);
}

unittest
{
    alias VoidResult = Result!(void, ResultTestError);
    auto success = VoidResult.ok();
    assert(success);

    int calls;
    auto mapped = move(success).map!(() { ++calls; return 5; });
    assert(mapped && mapped.value == 5 && calls == 1);

    auto chained = VoidResult.ok().andThen!(() => Result!(int, ResultTestError).ok(8));
    assert(chained && chained.value == 8);

    auto failure = VoidResult.err(ResultTestError.second);
    auto untouched = move(failure).map!(() { ++calls; });
    static assert(is(typeof(untouched) == VoidResult));
    assert(untouched.isErr && untouched.error == ResultTestError.second);
    assert(calls == 1);
}

unittest
{
    int destructions;
    {
        TrackedResultValue source = TrackedResultValue(&destructions, 7, true);
        auto result = Result!(TrackedResultValue, ResultTestError).ok(move(source));
        assert(result.value.value == 7);
        TrackedResultValue extracted = result.take();
        assert(result.isEmpty);
        assert(destructions == 0);
    }
    assert(destructions == 1);

    static assert(!__traits(compiles,
        (ref Result!(TrackedResultValue, ResultTestError) value)
        {
            Result!(TrackedResultValue, ResultTestError) copy = value;
        }));
}
