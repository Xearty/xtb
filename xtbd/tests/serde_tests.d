module tests.serde_tests;

import xtb.core.memory : AllocationRecord, InstrumentedAllocator, mallocAllocator;
import xtb.core.print : Writer;
import xtb.core.string : String, StringBuf, append, equal;
import xtb.serde.attributes;
import xtb.serde.casing;
import xtb.serde.error;
import xtb.serde.json;
import xtb.serde.ownership;
import xtb.serde.traits;

private size_t bufferSink(void* context, scope String bytes) nothrow @nogc
{
    StringBuf* output = cast(StringBuf*) context;
    (*output).append(bytes);
    return bytes.length;
}

private size_t failingSink(void*, scope String) nothrow @nogc
{
    return 0;
}

private enum Mode
{
    quiet,
    verbose,
}

@fieldCase(KeyCase.snake)
private struct Identity
{
    @required String displayName;
    uint userID;
}

private struct Settings
{
    @rename("api-version") int apiVersion;
    @aliasName("enabled") bool active;
    @ignore int transientValue;
    @omitDefault uint retries;
    @flatten Identity identity;
    Mode mode;
    int[] ports;
    int[2] pair;
}

private struct OptionalChild
{
    String label;
    int value;
}

private struct OptionalDocument
{
    OptionalChild* child;
}

private struct CasingDocument
{
    uint HTTPServerID;
    @rename("fixed-key") uint explicitName;
}

private void testJsonRoundTrip() nothrow @nogc
{
    int[3] ports = [80, 443, 8080];
    Settings settings;
    settings.apiVersion = 3;
    settings.active = true;
    settings.identity.displayName = "Ada \"L\"";
    settings.identity.userID = 42;
    settings.mode = Mode.verbose;
    settings.ports = ports[];
    settings.pair = [7, 9];

    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    JsonWriteOptions writeOptions;
    writeOptions.pretty = true;
    SerdeError error = writeJson(writer, settings, writeOptions);
    assert(error.ok);
    assert(encoded.view.equal(
            "{\n" ~
            "  \"api-version\": 3,\n" ~
            "  \"active\": true,\n" ~
            "  \"display_name\": \"Ada \\\"L\\\"\",\n" ~
            "  \"user_id\": 42,\n" ~
            "  \"mode\": \"verbose\",\n" ~
            "  \"ports\": [\n" ~
            "    80,\n" ~
            "    443,\n" ~
            "    8080\n" ~
            "  ],\n" ~
            "  \"pair\": [\n" ~
            "    7,\n" ~
            "    9\n" ~
            "  ]\n" ~
            "}"));

    Deserialized!Settings decoded;
    error = readJson(encoded.view, mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.apiVersion == 3);
    assert(decoded.value.active);
    assert(decoded.value.identity.displayName.equal("Ada \"L\""));
    assert(decoded.value.identity.userID == 42);
    assert(decoded.value.mode == Mode.verbose);
    assert(decoded.value.ports.length == 3);
    assert(decoded.value.ports[2] == 8080);
    assert(decoded.value.pair == [7, 9]);
}

private void testJsonPolicies() nothrow @nogc
{
    Deserialized!Settings decoded;
    SerdeError error = readJson(
        "{\"api-version\":1,\"enabled\":true,\"display_name\":\"x\"," ~
            "\"user_id\":1,\"mode\":\"quiet\",\"ports\":[],\"pair\":[1,2]}",
        mallocAllocator(),
        &decoded,
    );
    assert(error.ok);
    assert(decoded.value.active);

    error = readJson(
        "{\"api-version\":1,\"display_name\":\"x\",\"display_name\":\"y\"}",
        mallocAllocator(),
        &decoded,
    );
    assert(error.kind == SerdeErrorKind.duplicateField);
    assert(decoded.empty);

    error = readJson("{\"api-version\":1}", mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.missingRequiredField);

    error = readJson(
        "{\"api-version\":1,\"display_name\":\"x\",\"mystery\":1}",
        mallocAllocator(),
        &decoded,
    );
    assert(error.kind == SerdeErrorKind.unknownField);

    JsonReadOptions options;
    options.limits.ignoreUnknownFields = true;
    error = readJson(
        "{\"api-version\":1,\"display_name\":\"x\",\"unknown\":[1,{\"x\":2}]}",
        mallocAllocator(),
        &decoded,
        options,
    );
    assert(error.ok);
    assert(decoded.value.identity.displayName.equal("x"));
}

private void testJsonUnicodeAndNumbers() nothrow @nogc
{
    OptionalDocument document;
    Deserialized!OptionalDocument decoded;
    SerdeError error = readJson(
        "{\"child\":{\"label\":\"A\\u00df\\u6771\\ud834\\udd1e\",\"value\":-2147483648}}",
        mallocAllocator(),
        &decoded,
    );
    assert(error.ok);
    assert(decoded.value.child !is null);
    assert(decoded.value.child.label.equal("Aß東𝄞"));
    assert(decoded.value.child.value == int.min);

    error = readJson("{\"child\":{\"label\":\"\\ud800\"}}",
        mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.invalidEscape);
    assert(decoded.empty);

    error = readJson("{\"child\":{\"label\":\"x\",\"value\":2147483648}}",
        mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.numberOutOfRange);

    error = readJson("{\"child\":null}", mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.child is null);

    ubyte[3] invalidBytes = ['{', '"', 0xff];
    error = readJson(cast(String) invalidBytes[], mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.invalidUtf8 ||
            error.kind == SerdeErrorKind.unexpectedEnd);
    document.child = null;
}

private void testJsonCasingAndOutputFailure() nothrow @nogc
{
    CasingDocument value = CasingDocument(7, 9);
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    JsonWriteOptions options;
    options.keyCase = KeyCase.snake;
    SerdeError error = writeJson(writer, value, options);
    assert(error.ok);
    assert(encoded.view.equal("{\"http_server_id\":7,\"fixed-key\":9}"));

    Deserialized!CasingDocument decoded;
    JsonReadOptions readOptions;
    readOptions.keyCase = KeyCase.snake;
    error = readJson(encoded.view, mallocAllocator(), &decoded, readOptions);
    assert(error.ok);
    assert(decoded.value.HTTPServerID == 7);

    Writer failed = Writer.fromSink(&failingSink, null);
    error = writeJson(failed, value, options);
    assert(error.kind == SerdeErrorKind.outputFailure);
}

private void testJsonAllocationFailures() nothrow @nogc
{
    enum input = "{\"child\":{\"label\":\"allocated\",\"value\":7}}";
    bool reachedSuccess;
    foreach (allowed; 0 .. 8)
    {
        AllocationRecord[16] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        Deserialized!OptionalDocument decoded;
        SerdeError error = readJson(input, allocator.handle, &decoded);
        if (error.ok)
        {
            assert(decoded.value.child.label.equal("allocated"));
            decoded.deinit();
            reachedSuccess = true;
        }
        else
        {
            assert(error.kind == SerdeErrorKind.allocationFailure);
            assert(decoded.empty);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);
}

extern (C) int main()
{
    static foreach (testFunction; __traits(getUnitTests, xtb.serde.casing))
        testFunction();
    testJsonRoundTrip();
    testJsonPolicies();
    testJsonUnicodeAndNumbers();
    testJsonCasingAndOutputFailure();
    testJsonAllocationFailures();
    return 0;
}
