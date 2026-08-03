module examples.option_demo;

nothrow @nogc:

import core.lifetime : move;
import xtb.core.memory : Allocator, mallocAllocator;
import xtb.core.option : Option, none, reset, set, some, take;
import xtb.core.print : Writer, writeln;
import xtb.core.string : String, StringBuf, append, asStringUnchecked;
import xtb.core.types : u8;
import xtb.serde : KeyCase, SerdeError, fieldCase, readJson, readToml,
    required, writeJson, writeToml;

private struct LifetimeProbe
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

@fieldCase(KeyCase.snake)
private struct OptionalConfig
{
    // Required means that the input key must exist. For JSON, its value may
    // still be null, in which case the Option remains empty.
    @required Option!bool enabled;
    Option!StringBuf channelName;
    Option!uint retryCount;
}

private size_t appendSink(void* context, scope const(u8)[] bytes)
{
    StringBuf* output = cast(StringBuf*) context;
    (*output).append(bytes.asStringUnchecked);
    return bytes.length;
}

private void demonstrateValueState()
{
    // All three spellings create the same empty value. Option.init is useful
    // because it makes an uninitialized-looking declaration safely empty.
    Option!int implicitNone;
    Option!int staticNone = Option!int.none();
    Option!int genericNone = none!int();
    assert(implicitNone.isNone);
    assert(staticNone.isNone && genericNone.isNone);
    // `empty` exists for range-oriented generic code. Direct Option code should
    // communicate intent with isNone instead.
    assert(implicitNone.empty);
    assert(implicitNone.pointer is null);

    Option!int number = some(10);
    Option!int staticSome = Option!int.some(20);
    assert(number.isSome && staticSome.isSome && staticSome.value == 20);

    // value returns a checked reference. Calling it while empty is a contract
    // violation and panics, so test isSome/isNone or use pointer first.
    number.value += 1;
    if (int* value = number.pointer)
        *value += 9;
    writeln("present number after ref and pointer mutation: ", number.value);

    // A const Option exposes a pointer/reference to const T.
    const Option!int readOnly = number;
    const(int)* readOnlyPointer = readOnly.pointer;
    assert(readOnly.value == 20);
    assert(readOnlyPointer !is null && *readOnlyPointer == 20);

    // set replaces the old value. reset destroys it and returns to the empty
    // state. Both are mutating UFCS operations.
    number.set(42);
    assert(number.value == 42);
    number.reset();
    assert(number.isNone && number.pointer is null);

    // take transfers the value out and leaves the Option empty.
    number.set(99);
    int extracted = number.take();
    assert(extracted == 99 && number.isNone);
    writeln("taken number: ", extracted);
}

private void demonstrateCopyingAndNesting()
{
    // Option follows T's copyability. Copies of copyable values are
    // independent.
    Option!int original = some(7);
    Option!int copied = original;
    original.set(8);
    assert(original.value == 8 && copied.value == 7);

    // Nested options are legal core values and express three states. Avoid
    // them in serde schemas: JSON null collapses the first two states, and TOML
    // cannot represent a present outer Option containing an empty inner one.
    Option!(Option!int) missingOuter;
    Option!(Option!int) missingInner = some(none!int());
    Option!(Option!int) presentInner = some(some(123));
    assert(missingOuter.isNone);
    assert(missingInner.isSome && missingInner.value.isNone);
    assert(presentInner.value.value == 123);

    // Option only tracks its own presence bit. If T is itself nullable, a
    // present Option can legitimately contain T.init.
    Option!(int*) presentNullPointer = some(cast(int*) null);
    assert(presentNullPointer.isSome);
    assert(presentNullPointer.value is null);
    writeln("nested states and present-null pointer are distinct in memory");
}

private void demonstrateOwningValues(Allocator* allocator)
{
    StringBuf source = StringBuf.fromString(allocator, "alpha");
    Option!StringBuf text = some(move(source));

    // Moving transfers ownership and leaves the source at StringBuf.init.
    assert(source.allocator is null);
    text.value.append("-beta");
    writeln("owned option: ", text.value.view);

    // An Option is non-copyable when T is non-copyable.
    static assert(!__traits(compiles, (ref Option!StringBuf value) { Option!StringBuf copy = value; }));

    StringBuf extracted = text.take();
    assert(text.isNone && extracted == "alpha-beta");

    // set takes its argument by value. Pass move(...) for an owning T.
    text.set(move(extracted));
    text.reset();
    assert(text.isNone);
}

private void demonstrateDestruction()
{
    int destructions;
    {
        LifetimeProbe first = LifetimeProbe(&destructions, true);
        Option!LifetimeProbe tracked = some(move(first));

        // Replacing a present value destroys the previous value immediately.
        LifetimeProbe second = LifetimeProbe(&destructions, true);
        tracked.set(move(second));
        assert(destructions == 1);

        // reset likewise destroys a present value immediately.
        tracked.reset();
        assert(destructions == 2);

        LifetimeProbe third = LifetimeProbe(&destructions, true);
        tracked.set(move(third));

        // take transfers destruction responsibility to the returned value.
        LifetimeProbe extracted = tracked.take();
        assert(tracked.isNone && destructions == 2);
    }
    assert(destructions == 3);
    writeln("destructions after replace, reset, and taken-value scope exit: ",
        destructions);
}

private bool demonstrateSerde(Allocator* allocator)
{
    OptionalConfig config;
    config.enabled.set(true);
    config.retryCount.set(3);

    StringBuf json = StringBuf.create(allocator);
    Writer jsonWriter = Writer.fromSink(&appendSink, &json);
    SerdeError error = writeJson(jsonWriter, config);
    if (!error.ok)
        return false;

    // JSON writes every absent Option as null.
    assert(json ==
            "{\"enabled\":true,\"channel_name\":null,\"retry_count\":3}");
    writeln("JSON options: ", json.view);

    StringBuf toml = StringBuf.create(allocator);
    Writer tomlWriter = Writer.fromSink(&appendSink, &toml);
    error = writeToml(tomlWriter, config);
    if (!error.ok)
        return false;

    // TOML has no null, so absent option fields are omitted.
    assert(toml == "enabled = true\nretry_count = 3");
    writeln("TOML options:\n", toml.view);

    OptionalConfig fromJson;
    error = readJson(
        "{\"enabled\":null,\"channel_name\":\"nightly\"}",
        allocator,
        &fromJson,
    );
    if (!error.ok)
        return false;
    assert(fromJson.enabled.isNone);
    assert(fromJson.channelName.value == "nightly");
    assert(fromJson.retryCount.isNone);

    OptionalConfig fromToml;
    error = readToml(
        "enabled = false\nchannel_name = \"stable\"\n",
        allocator,
        &fromToml,
    );
    if (!error.ok)
        return false;
    assert(fromToml.enabled.isSome && !fromToml.enabled.value);
    assert(fromToml.channelName.value == "stable");
    assert(fromToml.retryCount.isNone);

    writeln("required JSON null -> none: ", fromJson.enabled.isNone);
    writeln("decoded TOML channel: ", fromToml.channelName.value.view);
    return true;
}

extern (C) int main()
{
    Allocator* allocator = mallocAllocator();
    demonstrateValueState();
    demonstrateCopyingAndNesting();
    demonstrateOwningValues(allocator);
    demonstrateDestruction();
    return demonstrateSerde(allocator) ? 0 : 1;
}
