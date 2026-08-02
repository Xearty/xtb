module tests.serde_backend_contract;

nothrow @nogc:

import xtb.core.memory : Allocator, mallocAllocator;
import xtb.core.option : Option;
import xtb.core.print : Writer;
import xtb.core.string : String, StringBuf, append, equal;
import xtb.serde : Deserialized, KeyCase, SerdeError, SerdeErrorKind,
    aliasName, defaultValue, fieldCase, omitDefault, readJson, readToml,
    required, writeJson, writeToml;

private size_t bufferSink(void* context, scope String bytes)
{
    StringBuf* output = cast(StringBuf*) context;
    (*output).append(bytes);
    return bytes.length;
}

private struct ContractChild
{
    bool enabled;
}

@fieldCase(KeyCase.snake)
private struct ContractDocument
{
    @required String serviceName;
    @aliasName("attempts") int retryCount;
    @defaultValue(3) @omitDefault int retryWindow;
    Option!int priority;
    ContractChild child;
}

private struct JsonBackend
{
nothrow @nogc:

    enum expected =
        "{\"service_name\":\"api\",\"retry_count\":2," ~
        "\"priority\":null,\"child\":{\"enabled\":true}}";
    enum legacy =
        "{\"service_name\":\"legacy\",\"attempts\":4," ~
        "\"child\":{\"enabled\":false}}";
    enum missingRequired = "{\"retry_count\":1}";
    enum unknown = "{\"service_name\":\"api\",\"unknown\":1}";

    static SerdeError write(ref Writer writer, scope const ref ContractDocument value)
    {
        return writeJson(writer, value);
    }

    static SerdeError read(
        scope String input,
        Allocator* allocator,
        Deserialized!ContractDocument* output,
    )
    {
        return readJson(input, allocator, output);
    }
}

private struct TomlBackend
{
nothrow @nogc:

    enum expected =
        "service_name = \"api\"\n" ~
        "retry_count = 2\n" ~
        "child = { enabled = true }";
    enum legacy =
        "service_name = \"legacy\"\n" ~
        "attempts = 4\n" ~
        "child = { enabled = false }\n";
    enum missingRequired = "retry_count = 1\n";
    enum unknown = "service_name = \"api\"\nunknown = 1\n";

    static SerdeError write(ref Writer writer, scope const ref ContractDocument value)
    {
        return writeToml(writer, value);
    }

    static SerdeError read(
        scope String input,
        Allocator* allocator,
        Deserialized!ContractDocument* output,
    )
    {
        return readToml(input, allocator, output);
    }
}

private void runBackendContract(Backend)()
{
    ContractDocument value;
    value.serviceName = "api";
    value.retryCount = 2;
    value.retryWindow = 3;
    value.child.enabled = true;

    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    SerdeError error = Backend.write(writer, value);
    assert(error.ok);
    assert(encoded == Backend.expected);

    Deserialized!ContractDocument roundTrip;
    error = Backend.read(encoded.view, mallocAllocator(), &roundTrip);
    assert(error.ok);
    assert(roundTrip.value.serviceName.equal("api"));
    assert(roundTrip.value.retryCount == 2);
    assert(roundTrip.value.retryWindow == 3);
    assert(roundTrip.value.priority.isNone);
    assert(roundTrip.value.child.enabled);

    Deserialized!ContractDocument legacy;
    error = Backend.read(Backend.legacy, mallocAllocator(), &legacy);
    assert(error.ok);
    assert(legacy.value.serviceName.equal("legacy"));
    assert(legacy.value.retryCount == 4);
    assert(legacy.value.retryWindow == 3);
    assert(legacy.value.priority.isNone);
    assert(!legacy.value.child.enabled);

    error = Backend.read(Backend.missingRequired, mallocAllocator(), &legacy);
    assert(error.kind == SerdeErrorKind.missingRequiredField);
    assert(legacy.empty);

    error = Backend.read(Backend.unknown, mallocAllocator(), &legacy);
    assert(error.kind == SerdeErrorKind.unknownField);
    assert(legacy.empty);
}

void runSerdeBackendContracts()
{
    runBackendContract!JsonBackend();
    runBackendContract!TomlBackend();
}
