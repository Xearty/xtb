module xtb.core.result;

nothrow @nogc:

import core.attribute : mustuse;
import core.internal.traits : hasElaborateCopyConstructor, hasElaborateDestructor;
import core.lifetime : forward;
import xtb.core.lifetime : deinitValue = deinit, move, moveEmplace, needsDeinit;
import xtb.core.panic : panic;
import xtb.core.types : String;

version (XTB_Checked) import xtb.core.panic : require;

private enum ResultState : ubyte
{
    ok,
    err,
}

private template isCopyableResultValue(T)
{
    static if (is(T == void))
        enum bool isCopyableResultValue = true;
    else
        enum bool isCopyableResultValue = __traits(isCopyable, T) &&
            !needsDeinit!T && !hasElaborateCopyConstructor!T;
}

private template isMonadicValue(T)
{
    static if (is(T == void))
        enum bool isMonadicValue = true;
    else
        enum bool isMonadicValue = !needsDeinit!T &&
            !hasElaborateDestructor!T && !hasElaborateCopyConstructor!T;
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
/// A Result has exactly two logical states: `Ok(T)` and `Err(E)`. There is no
/// empty state. Default construction is disabled; construct through `ok` or
/// `err`.
///
/// `take`/`unwrap` and `takeError`/`unwrapError` transfer the active payload
/// without cleaning it. The Result remains in the same logical branch with a
/// safely moved-from payload. Checked builds diagnose repeated semantic use of
/// a consumed Result; that diagnostic bit is not a third Result state.
@mustuse struct Result(T, E)
{
nothrow @nogc:

    static assert(!is(E == void), "Result error type cannot be void");

    private ResultState state_;
    static if (!is(T == void))
        align(T.alignof) private ubyte[T.sizeof] valueStorage_;
    align(E.alignof) private ubyte[E.sizeof] errorStorage_;
    version (XTB_Checked) private bool consumed_;

    @disable this();

    static if (!isCopyableResultValue!T || !isCopyableResultValue!E)
        @disable this(this);

    static if (!is(T == void))
    {
        private ref inout(T) valuePayload() inout return @system
        {
            return *cast(inout(T)*) valueStorage_.ptr;
        }
    }

    private ref inout(E) errorPayload() inout return @system
    {
        return *cast(inout(E)*) errorStorage_.ptr;
    }

    /// Replaces this Result by consuming `source`.
    ///
    /// Cleanup-bearing Results require an rvalue/moved source because implicit
    /// owner copying is disabled.
    ref Result opAssign(Result source) return
    {
        version (XTB_Checked)
            require(!source.consumed_, "cannot assign from a consumed Result");

        deinit();
        state_ = source.state_;
        static if (!is(T == void))
        {
            if (source.state_ == ResultState.ok)
                moveEmplace(source.valuePayload(), valuePayload());
            else
                moveEmplace(source.errorPayload(), errorPayload());
        }
        else
        {
            if (source.state_ == ResultState.err)
                moveEmplace(source.errorPayload(), errorPayload());
        }
        version (XTB_Checked)
        {
            consumed_ = false;
            source.consumed_ = true;
        }
        return this;
    }

    static if (is(T == void))
    {
        static Result ok()
        {
            Result result = void;
            result.state_ = ResultState.ok;
            version (XTB_Checked) result.consumed_ = false;
            return result;
        }
    }
    else
    {
        static Result ok(T value)
        {
            Result result = void;
            moveEmplace(value, result.valuePayload());
            result.state_ = ResultState.ok;
            version (XTB_Checked) result.consumed_ = false;
            return result;
        }
    }

    static Result err(E error)
    {
        Result result = void;
        moveEmplace(error, result.errorPayload());
        result.state_ = ResultState.err;
        version (XTB_Checked) result.consumed_ = false;
        return result;
    }

    /// Rebinds an error from another Result with the same error type.
    ///
    /// The source must currently be an error. Its error payload is transferred
    /// and the source remains `Err` with a moved-from payload.
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

    /// Converts to true exactly when this Result is successful.
    bool opCast(U : bool)() const pure @safe
    {
        return isOk;
    }

    /// Explicitly ends this Result's lifetime by cleaning only its active
    /// branch. A moved-from active payload is safe to deinitialize.
    void deinit()
    {
        if (state_ == ResultState.ok)
        {
            static if (!is(T == void))
            {
                static if (needsDeinit!T)
                    deinitValue(valuePayload());
                else static if (hasElaborateDestructor!T)
                    destroy(valuePayload());
            }
        }
        else
        {
            static if (needsDeinit!E)
                deinitValue(errorPayload());
            else static if (hasElaborateDestructor!E)
                destroy(errorPayload());
        }
    }

    static if (!is(T == void))
    {
        ref inout(T) value() inout return @system
        {
            version (XTB_Checked)
            {
                require(!consumed_, "consumed Result has no usable value");
                require(isOk, "Result does not contain a value");
            }
            return valuePayload();
        }

        /// Transfers the success value out. The Result stays logically `Ok`
        /// with a moved-from payload.
        T take()
        {
            version (XTB_Checked)
            {
                require(!consumed_, "cannot take from a consumed Result");
                require(isOk, "cannot take the value of a non-ok Result");
            }
            T result = void;
            moveEmplace(valuePayload(), result);
            version (XTB_Checked) consumed_ = true;
            return result;
        }

        /// Transfers the success value out or panics unless this Result is ok.
        T unwrap()
        {
            version (XTB_Checked)
                if (consumed_)
                    panic("called Result.unwrap() on a consumed Result");
            if (!isOk)
                panic("called Result.unwrap() on err");
            return take();
        }

        /// Transfers the success value out or panics with `message` unless ok.
        T expect(String message)
        {
            version (XTB_Checked)
                if (consumed_)
                    panic(message);
            if (!isOk)
                panic(message);
            return take();
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
                require(!consumed_, "cannot take from a consumed Result");
                require(isOk, "cannot take the value of a non-ok Result");
                consumed_ = true;
            }
        }

        /// Consumes this Result or panics unless it is ok.
        void unwrap()
        {
            version (XTB_Checked)
                if (consumed_)
                    panic("called Result.unwrap() on a consumed Result");
            if (!isOk)
                panic("called Result.unwrap() on err");
            take();
        }

        /// Consumes this Result or panics with `message` unless it is ok.
        void expect(String message)
        {
            version (XTB_Checked)
                if (consumed_)
                    panic(message);
            if (!isOk)
                panic(message);
            take();
        }
    }

    ref inout(E) error() inout return @system
    {
        version (XTB_Checked)
        {
            require(!consumed_, "consumed Result has no usable error");
            require(isErr, "Result does not contain an error");
        }
        return errorPayload();
    }

    /// Transfers the error out. The Result stays logically `Err` with a
    /// moved-from payload.
    E takeError()
    {
        version (XTB_Checked)
        {
            require(!consumed_, "cannot take from a consumed Result");
            require(isErr, "cannot take the error of a non-error Result");
        }
        E result = void;
        moveEmplace(errorPayload(), result);
        version (XTB_Checked) consumed_ = true;
        return result;
    }

    /// Transfers the error out or panics unless this Result is an error.
    E unwrapError()
    {
        version (XTB_Checked)
            if (consumed_)
                panic("called Result.unwrapError() on a consumed Result");
        if (!isErr)
            panic("called Result.unwrapError() on ok");
        return takeError();
    }

    /// Transfers the error out or panics with `message` unless this Result is an error.
    E expectError(String message)
    {
        version (XTB_Checked)
            if (consumed_)
                panic(message);
        if (!isErr)
            panic(message);
        return takeError();
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
    static assert(isMonadicValue!T && isMonadicValue!E,
        "Result.map currently supports only payloads without deinit or D destructor semantics");

    static if (is(T == void))
        alias U = typeof(transform(forward!args));
    else
        alias U = typeof(transform(result.take(), forward!args));
    static assert(isMonadicValue!U,
        "Result.map currently supports only result payloads without deinit or D destructor semantics");

    alias Mapped = Result!(U, E);
    if (result.isErr)
        return Mapped.err(result.takeError());

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

/// Transforms a simple error while preserving a simple success type.
auto mapError(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    static assert(isMonadicValue!T && isMonadicValue!E,
        "Result.mapError currently supports only payloads without deinit or D destructor semantics");
    alias F = typeof(transform(result.takeError(), forward!args));
    static assert(!is(F == void), "Result.mapError transform must return an error value");
    static assert(isMonadicValue!F,
        "Result.mapError currently supports only result payloads without deinit or D destructor semantics");
    alias Mapped = Result!(T, F);

    if (result.isErr)
    {
        F error = transform(result.takeError(), forward!args);
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
auto andThen(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    static assert(isMonadicValue!T && isMonadicValue!E,
        "Result.andThen currently supports only payloads without deinit or D destructor semantics");

    static if (is(T == void))
        alias Next = typeof(transform(forward!args));
    else
        alias Next = typeof(transform(result.take(), forward!args));

    static assert(isResultType!Next, "Result.andThen transform must return Result");
    static assert(is(ResultError!Next == E),
        "Result.andThen transform must preserve the error type; use mapError to convert errors");
    static assert(isMonadicValue!(ResultValue!Next) && isMonadicValue!(ResultError!Next),
        "Result.andThen currently supports only result payloads without deinit or D destructor semantics");

    if (result.isErr)
        return Next.err(result.takeError());

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

/// Recovers from a simple error with another simple Result-producing operation.
auto orElse(alias transform, T, E, Args...)(
    Result!(T, E) result,
    auto ref Args args,
)
{
    static assert(isMonadicValue!T && isMonadicValue!E,
        "Result.orElse currently supports only payloads without deinit or D destructor semantics");
    alias Next = typeof(transform(result.takeError(), forward!args));
    static assert(isResultType!Next, "Result.orElse transform must return Result");
    static assert(is(ResultValue!Next == T),
        "Result.orElse transform must preserve the success type; use map to convert values");
    static assert(isMonadicValue!(ResultValue!Next) && isMonadicValue!(ResultError!Next),
        "Result.orElse currently supports only result payloads without deinit or D destructor semantics");

    if (result.isErr)
        return transform(result.takeError(), forward!args);

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

    int* deinits;
    int value;
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

version (unittest) private struct DestructorResultValue
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
    static assert(!__traits(compiles, () { Result!(int, ResultTestError) value; }));

    auto success = Result!(int, ResultTestError).ok(42);
    assert(success.isOk && !success.isErr);
    assert(success);
    assert(success.value == 42);
    success.value += 1;
    assert(success.unwrap() == 43);
    assert(success.isOk);

    auto expectedSuccess = Result!(int, ResultTestError).ok(44);
    assert(expectedSuccess.expect("expected success") == 44);
    assert(expectedSuccess.isOk);

    auto failure = Result!(int, ResultTestError).err(ResultTestError.second);
    assert(!failure);
    assert(failure.isErr && failure.error == ResultTestError.second);
    assert(failure.unwrapError() == ResultTestError.second);
    assert(failure.isErr);

    auto expectedFailure = Result!(int, ResultTestError).err(ResultTestError.first);
    assert(expectedFailure.expectError("expected error") == ResultTestError.first);
    assert(expectedFailure.isErr);

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
    success.unwrap();
    assert(success.isOk);

    auto expectedSuccess = VoidResult.ok();
    expectedSuccess.expect("expected void success");
    assert(expectedSuccess.isOk);

    int calls;
    success = VoidResult.ok();
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
    int deinits;
    TrackedResultValue source = TrackedResultValue(&deinits, 7, true);
    auto result = Result!(TrackedResultValue, ResultTestError).ok(move(source));
    assert(result.value.value == 7);
    TrackedResultValue extracted = result.take();
    assert(result.isOk);
    assert(deinits == 0);
    deinitValue(result);
    assert(deinits == 0);
    deinitValue(extracted);
    assert(deinits == 1);

    TrackedResultValue replacementValue = TrackedResultValue(&deinits, 8, true);
    auto replacement = Result!(TrackedResultValue, ResultTestError).ok(move(replacementValue));
    TrackedResultValue oldValue = TrackedResultValue(&deinits, 9, true);
    auto target = Result!(TrackedResultValue, ResultTestError).ok(move(oldValue));
    target = move(replacement);
    assert(deinits == 2);
    assert(target.value.value == 8);
    deinitValue(target);
    assert(deinits == 3);

    static assert(!__traits(compiles,
            (ref Result!(TrackedResultValue, ResultTestError) value) {
            Result!(TrackedResultValue, ResultTestError) copy = value;
        }));
    static assert(!__traits(compiles,
            (Result!(TrackedResultValue, ResultTestError) value) {
            return value.map!(item => item.value);
        }));
}

unittest
{
    static assert(!hasElaborateDestructor!(
            Result!(DestructorResultValue, ResultTestError)));
    static assert(!hasElaborateDestructor!(
            Result!(int, DestructorResultValue)));

    int destructions;
    DestructorResultValue successValue =
        DestructorResultValue(&destructions, true);
    auto success = Result!(DestructorResultValue, ResultTestError)
        .ok(move(successValue));
    deinitValue(success);
    assert(destructions == 1);

    DestructorResultValue errorValue =
        DestructorResultValue(&destructions, true);
    auto failure = Result!(int, DestructorResultValue).err(move(errorValue));
    deinitValue(failure);
    assert(destructions == 2);

    DestructorResultValue transferredValue =
        DestructorResultValue(&destructions, true);
    auto transferred = Result!(DestructorResultValue, ResultTestError)
        .ok(move(transferredValue));
    DestructorResultValue extracted = transferred.take();
    deinitValue(transferred);
    assert(destructions == 2);
    destroy(extracted);
    assert(destructions == 3);
}
