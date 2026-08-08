module examples.result_demo;

nothrow @nogc:

import xtb.core : Result, ResultReturns, andThen, map, mapError, orElse;

private enum DemoError
{
    unavailable,
    invalid,
}

private Result!(int, DemoError) readValue(bool fail)
{
    mixin ResultReturns;
    if (fail)
        return err(DemoError.unavailable);
    return ok(20);
}

private Result!(long, DemoError) loadAndScale(bool fail)
{
    mixin ResultReturns;

    auto value = readValue(fail);
    if (!value)
        return err(value);

    return ok(value.take() * 2L);
}

private Result!(long, DemoError) widen(int value)
{
    mixin ResultReturns;
    if (value < 0)
        return err(DemoError.invalid);
    return ok(cast(long) value);
}

extern (C) int main()
{
    auto success = loadAndScale(false);
    assert(success && success.value == 40);

    auto failure = loadAndScale(true);
    assert(!failure && failure.error == DemoError.unavailable);

    auto unwrapped = loadAndScale(false);
    assert(unwrapped.unwrap() == 40 && unwrapped.isEmpty);
    auto unwrappedError = loadAndScale(true);
    assert(unwrappedError.unwrapError() == DemoError.unavailable);

    int offset = 2;
    auto pipeline = readValue(false)
        .map!(value => value + offset)
        .andThen!widen()
        .map!(value => value * 3L);
    assert(pipeline && pipeline.value == 66);

    auto convertedError = readValue(true)
        .mapError!(error => cast(int) error + 100);
    assert(convertedError.isErr && convertedError.error == 100);

    auto recovered = readValue(true).orElse!(error =>
            Result!(int, int).ok(error == DemoError.unavailable ? 7 : 0));
    assert(recovered && recovered.value == 7);
    return 0;
}
