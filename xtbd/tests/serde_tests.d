module tests.serde_tests;

import core.lifetime : move;
import tests.serde_backend_contract : runSerdeBackendContracts;
import xtb.core.array : Array, append;
import xtb.core.memory : AllocationRecord, Allocator, InstrumentedAllocator,
    mallocAllocator;
import xtb.core.option : Option, set;
import xtb.core.print : Writer;
import xtb.core.string : String, StringBuf, append, clear, equal;
import xtb.serde.attributes;
import xtb.serde.casing;
import xtb.serde.error;
import xtb.serde.json;
import xtb.serde.ownership;
import xtb.serde.toml;
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

@variantCase(KeyCase.snake)
private enum DeploymentMode
{
    blueGreen,
    @rename("rolling-update") @aliasName("rolling") rollingUpdate,
}

bool omitSeven(scope const ref int value) nothrow @nogc pure @safe
{
    return value == 7;
}

private struct PolicyDocument
{
    DeploymentMode mode;
    @defaultValue(7) @omitIf!omitSeven int retryLimit;
}

private struct Percentage
{
    ubyte value;
}

struct PercentageSerde
{
    alias Representation = uint;

    static SerdeErrorKind encode(
        scope const ref Percentage value,
        uint* output,
    ) nothrow @nogc
    {
        *output = value.value;
        return SerdeErrorKind.none;
    }

    static SerdeErrorKind decode(
        scope const ref uint value,
        Allocator*,
        Percentage* output,
    ) nothrow @nogc
    {
        if (value > 100)
            return SerdeErrorKind.numberOutOfRange;
        output.value = cast(ubyte) value;
        return SerdeErrorKind.none;
    }
}

private struct AdapterDocument
{
    @withSerde!PercentageSerde Percentage percentage;
}

static assert(fieldAdapterCount!(AdapterDocument, 0) == 1);

private struct SwitchState
{
    bool enabled;
}

struct SwitchStateSerde
{
    alias Representation = String;

    static SerdeErrorKind encode(
        scope const ref SwitchState value,
        String* output,
    ) nothrow @nogc
    {
        *output = value.enabled ? "enabled" : "disabled";
        return SerdeErrorKind.none;
    }

    static SerdeErrorKind decode(
        scope const ref String value,
        Allocator*,
        SwitchState* output,
    ) nothrow @nogc
    {
        if (value.equal("enabled"))
            output.enabled = true;
        else if (value.equal("disabled"))
            output.enabled = false;
        else
            return SerdeErrorKind.typeMismatch;
        return SerdeErrorKind.none;
    }
}

private struct StringAdapterDocument
{
    @withSerde!SwitchStateSerde SwitchState state;
}

private struct ExplicitNestedDefault
{
    @defaultValue(11) int value;
}

private struct NestedDefaultsDocument
{
    ExplicitNestedDefault* pointer;
    ExplicitNestedDefault[] items;
}

@variantCase(KeyCase.snake)
private enum EventKind
{
    recordCreated,
    @rename("removed") @aliasName("record_deleted") recordDeleted,
}

private struct CreatedEvent
{
    int id;
    String displayName;
}

private struct DeletedEvent
{
    int id;
    bool permanent;
}

private union EventPayload
{
    @caseOf(EventKind.recordCreated) CreatedEvent created;
    @caseOf(EventKind.recordDeleted) DeletedEvent deleted;
}

@taggedUnion(TagLayout.external)
private struct ExternalEvent
{
    @discriminant EventKind kind;
    @payload EventPayload data;
}

@taggedUnion(TagLayout.internal)
private struct InternalEvent
{
    @discriminant @rename("event_type") EventKind kind;
    @payload EventPayload data;
}

@taggedUnion(TagLayout.adjacent)
private struct AdjacentEvent
{
    @discriminant @rename("event_type") EventKind kind;
    @payload @rename("event_data") EventPayload data;
}

private struct ExternalEnvelope
{
    ExternalEvent event;
}

private struct InternalEnvelope
{
    InternalEvent event;
}

private struct AdjacentEnvelope
{
    AdjacentEvent event;
}

private enum ScalarKind
{
    integer,
}

private union ScalarPayload
{
    @caseOf(ScalarKind.integer) int integer;
}

@taggedUnion(TagLayout.internal)
private struct InvalidInternalUnion
{
    @discriminant ScalarKind kind;
    @payload ScalarPayload data;
}

private union IncompletePayload
{
    @caseOf(EventKind.recordCreated) CreatedEvent created;
}

@taggedUnion(TagLayout.adjacent)
private struct IncompleteUnion
{
    @discriminant EventKind kind;
    @payload IncompletePayload data;
}

struct InvalidSerdeAdapter
{
    alias Representation = uint;

    static bool encode(scope const ref Percentage, uint*)
    {
        return true;
    }

    static bool decode(scope const ref uint, Allocator*, Percentage*)
    {
        return true;
    }
}

private struct InvalidAdapterDocument
{
    @withSerde!InvalidSerdeAdapter Percentage percentage;
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

@fieldCase(KeyCase.snake)
private struct OptionalValues
{
    Option!String title;
    Option!int priority;
    Option!OptionalChild child;
    @required Option!bool explicitToggle;
}

private struct CasingDocument
{
    uint httpServerID;
    @rename("fixed-key") uint explicitName;
}

private struct Database
{
    @required String hostName;
    ushort port;
}

private struct Server
{
    String name;
    bool enabled;
}

@fieldCase(KeyCase.snake)
private struct TomlDocument
{
    @required String applicationName;
    Database database;
    Server[] servers;
    double ratio;
}

private struct DefaultsDocument
{
    @omitDefault int retryCount = 3;
    bool enabled;
}

@fieldCase(KeyCase.snake)
private struct ConflictingNames
{
    int fieldName;
    int field_name;
}

private struct StaticInitializer
{
    String text = "static storage";
}

align(64) private struct AlignedDocument
{
    int value;
}

@fieldCase(KeyCase.snake)
private struct OwnedEndpoint
{
    @required StringBuf hostName;
    ushort port;
    Array!StringBuf labels;
}

@fieldCase(KeyCase.snake)
private struct OwnedDocument
{
    @required StringBuf applicationName;
    OwnedEndpoint primaryEndpoint;
    Array!OwnedEndpoint replicaEndpoints;
    Array!StringBuf featureFlags;
    @omitDefault StringBuf description;
    @omitDefault Array!StringBuf experiments;
    int[3] retryDelays;
    @omitDefault bool tracingEnabled;
}

@fieldCase(KeyCase.snake)
private struct OwnedOptionalValues
{
    Option!StringBuf title;
    Option!OwnedEndpoint endpoint;
    Option!uint revision;
    @required Option!bool explicitToggle;
}

static assert(!__traits(compiles, validateSchema!ConflictingNames()));
static assert(__traits(compiles, validateSchema!StaticInitializer()));
static assert(__traits(compiles, validateOwnedSchema!OwnedDocument()));
static assert(__traits(compiles, validateOwnedSchema!OwnedOptionalValues()));
static assert(__traits(compiles, validateBorrowedSchema!OptionalValues()));
static assert(__traits(compiles, validateBorrowedSchema!ExternalEvent()));
static assert(__traits(compiles, validateBorrowedSchema!InternalEvent()));
static assert(__traits(compiles, validateBorrowedSchema!AdjacentEvent()));
static assert(!__traits(compiles, validateOwnedSchema!AdjacentEvent()));
static assert(!__traits(compiles,
        validateBorrowedSchema!InvalidInternalUnion()));
static assert(!__traits(compiles, validateBorrowedSchema!IncompleteUnion()));
static assert(!__traits(compiles, validateSchema!InvalidAdapterDocument()));
static assert(!__traits(compiles, validateBorrowedSchema!OwnedDocument()));
static assert(!__traits(compiles, validateOwnedSchema!Settings()));
static assert(!__traits(compiles, (ref Deserialized!Settings value) {
        Deserialized!Settings copy = value;
    }));

private void testSharedPolicies() nothrow @nogc
{
    PolicyDocument value;
    value.mode = DeploymentMode.rollingUpdate;
    value.retryLimit = 7;

    StringBuf json = StringBuf.create(mallocAllocator());
    Writer jsonWriter = Writer.fromSink(&bufferSink, &json);
    SerdeError error = writeJson(jsonWriter, value);
    assert(error.ok);
    assert(json == "{\"mode\":\"rolling-update\"}");

    Deserialized!PolicyDocument fromJson;
    error = readJson("{\"mode\":\"rolling\"}", mallocAllocator(),
        &fromJson);
    assert(error.ok);
    assert(fromJson.value.mode == DeploymentMode.rollingUpdate);
    assert(fromJson.value.retryLimit == 7);

    StringBuf toml = StringBuf.create(mallocAllocator());
    Writer tomlWriter = Writer.fromSink(&bufferSink, &toml);
    error = writeToml(tomlWriter, value);
    assert(error.ok);
    assert(toml == "mode = \"rolling-update\"");

    Deserialized!PolicyDocument fromToml;
    error = readToml("mode = \"blue_green\"", mallocAllocator(),
        &fromToml);
    assert(error.ok);
    assert(fromToml.value.mode == DeploymentMode.blueGreen);
    assert(fromToml.value.retryLimit == 7);

    AdapterDocument adapted = AdapterDocument(Percentage(75));
    json.clear();
    jsonWriter = Writer.fromSink(&bufferSink, &json);
    error = writeJson(jsonWriter, adapted);
    assert(error.ok);
    assert(json == "{\"percentage\":75}");
    AdapterDocument ownedJson;
    error = readJson(json.view, mallocAllocator(), &ownedJson);
    assert(error.ok);
    assert(ownedJson.percentage.value == 75);

    toml.clear();
    tomlWriter = Writer.fromSink(&bufferSink, &toml);
    error = writeToml(tomlWriter, adapted);
    assert(error.ok);
    assert(toml == "percentage = 75");
    AdapterDocument ownedToml;
    error = readToml(toml.view, mallocAllocator(), &ownedToml);
    assert(error.ok);
    assert(ownedToml.percentage.value == 75);

    error = readJson("{\"percentage\":101}", mallocAllocator(), &ownedJson);
    assert(error.kind == SerdeErrorKind.numberOutOfRange);
    error = readToml("percentage = 101", mallocAllocator(), &ownedToml);
    assert(error.kind == SerdeErrorKind.numberOutOfRange);

    AllocationRecord[16] adapterRecords;
    InstrumentedAllocator adapterAllocator = InstrumentedAllocator.create(
        mallocAllocator(), adapterRecords[]);
    {
        StringAdapterDocument stringAdapted;
        error = readJson("{\"state\":\"en\\u0061bled\"}",
            adapterAllocator.handle, &stringAdapted);
        assert(error.ok);
        assert(stringAdapted.state.enabled);
        error = readToml("state = \"disabled\"", adapterAllocator.handle,
            &stringAdapted);
        assert(error.ok);
        assert(!stringAdapted.state.enabled);
    }
    assert(adapterAllocator.clean);
    assert(adapterAllocator.stats.invalidCalls == 0);

    Deserialized!NestedDefaultsDocument jsonDefaults;
    error = readJson("{\"pointer\":{},\"items\":[{}]}",
        mallocAllocator(), &jsonDefaults);
    assert(error.ok);
    assert(jsonDefaults.value.pointer.value == 11);
    assert(jsonDefaults.value.items[0].value == 11);

    Deserialized!NestedDefaultsDocument tomlDefaults;
    error = readToml("pointer = {}\nitems = [{}]\n",
        mallocAllocator(), &tomlDefaults);
    assert(error.ok);
    assert(tomlDefaults.value.pointer.value == 11);
    assert(tomlDefaults.value.items[0].value == 11);
}

private void testJsonTaggedUnions() nothrow @nogc
{
    ExternalEvent external;
    external.kind = EventKind.recordCreated;
    external.data.created = CreatedEvent(17, "new record");
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    SerdeError error = writeJson(writer, external);
    assert(error.ok);
    assert(encoded ==
            "{\"record_created\":{\"id\":17,\"displayName\":\"new record\"}}");

    Deserialized!ExternalEvent decodedExternal;
    error = readJson(encoded.view, mallocAllocator(), &decodedExternal);
    assert(error.ok);
    assert(decodedExternal.value.kind == EventKind.recordCreated);
    assert(decodedExternal.value.data.created.id == 17);
    assert(decodedExternal.value.data.created.displayName.equal("new record"));

    InternalEvent internal;
    internal.kind = EventKind.recordDeleted;
    internal.data.deleted = DeletedEvent(9, true);
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, internal);
    assert(error.ok);
    assert(encoded ==
            "{\"event_type\":\"removed\",\"id\":9,\"permanent\":true}");

    Deserialized!InternalEvent decodedInternal;
    error = readJson(
        "{\"permanent\":true,\"id\":9,\"event_type\":\"record_deleted\"}",
        mallocAllocator(), &decodedInternal);
    assert(error.ok);
    assert(decodedInternal.value.kind == EventKind.recordDeleted);
    assert(decodedInternal.value.data.deleted.id == 9);
    assert(decodedInternal.value.data.deleted.permanent);

    AdjacentEvent adjacent;
    adjacent.kind = EventKind.recordCreated;
    adjacent.data.created = CreatedEvent(23, "adjacent");
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, adjacent);
    assert(error.ok);
    assert(encoded ==
            "{\"event_type\":\"record_created\",\"event_data\":{" ~
            "\"id\":23,\"displayName\":\"adjacent\"}}");

    Deserialized!AdjacentEvent decodedAdjacent;
    error = readJson(
        "{\"event_data\":{\"id\":23,\"displayName\":\"adjacent\"}," ~
            "\"event_type\":\"record_created\"}",
        mallocAllocator(), &decodedAdjacent);
    assert(error.ok);
    assert(decodedAdjacent.value.kind == EventKind.recordCreated);
    assert(decodedAdjacent.value.data.created.id == 23);

    error = readJson(
        "{\"event_type\":\"missing\",\"event_data\":{}}",
        mallocAllocator(), &decodedAdjacent);
    assert(error.kind == SerdeErrorKind.unknownVariant);
    assert(decodedAdjacent.empty);
}

private void testTomlTaggedUnions() nothrow @nogc
{
    ExternalEnvelope external;
    external.event.kind = EventKind.recordCreated;
    external.event.data.created = CreatedEvent(17, "new record");
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    SerdeError error = writeToml(writer, external);
    assert(error.ok);
    assert(encoded ==
            "event = { \"record_created\" = { id = 17, " ~
            "displayName = \"new record\" } }");

    Deserialized!ExternalEnvelope decodedExternal;
    error = readToml(encoded.view, mallocAllocator(), &decodedExternal);
    assert(error.ok);
    assert(decodedExternal.value.event.kind == EventKind.recordCreated);
    assert(decodedExternal.value.event.data.created.id == 17);

    InternalEnvelope internal;
    internal.event.kind = EventKind.recordDeleted;
    internal.event.data.deleted = DeletedEvent(9, true);
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, internal);
    assert(error.ok);
    assert(encoded ==
            "event = { event_type = \"removed\", id = 9, permanent = true }");

    Deserialized!InternalEnvelope decodedInternal;
    error = readToml(
        "event = { permanent = true, id = 9, " ~
            "event_type = \"record_deleted\" }",
        mallocAllocator(), &decodedInternal);
    assert(error.ok);
    assert(decodedInternal.value.event.kind == EventKind.recordDeleted);
    assert(decodedInternal.value.event.data.deleted.permanent);

    AdjacentEnvelope adjacent;
    adjacent.event.kind = EventKind.recordCreated;
    adjacent.event.data.created = CreatedEvent(23, "adjacent");
    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, adjacent);
    assert(error.ok);
    assert(encoded ==
            "event = { event_type = \"record_created\", event_data = { " ~
            "id = 23, displayName = \"adjacent\" } }");

    Deserialized!AdjacentEnvelope decodedAdjacent;
    error = readToml(
        "event = { event_data = { id = 23, displayName = \"adjacent\" }, " ~
            "event_type = \"record_created\" }",
        mallocAllocator(), &decodedAdjacent);
    assert(error.ok);
    assert(decodedAdjacent.value.event.kind == EventKind.recordCreated);
    assert(decodedAdjacent.value.event.data.created.id == 23);

    error = readToml(
        "event = { event_type = \"missing\", event_data = {} }",
        mallocAllocator(), &decodedAdjacent);
    assert(error.kind == SerdeErrorKind.unknownVariant);
    assert(decodedAdjacent.empty);

    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, adjacent.event);
    assert(error.ok);
    assert(encoded ==
            "event_type = \"record_created\"\n" ~
            "event_data = { id = 23, displayName = \"adjacent\" }");
    Deserialized!AdjacentEvent rootAdjacent;
    error = readToml(
        "event_data = { id = 23, displayName = \"adjacent\" }\n" ~
            "event_type = \"record_created\"\n",
        mallocAllocator(), &rootAdjacent);
    assert(error.ok);
    assert(rootAdjacent.value.data.created.id == 23);

    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, external.event);
    assert(error.ok);
    Deserialized!ExternalEvent rootExternal;
    error = readToml(encoded.view, mallocAllocator(), &rootExternal);
    assert(error.ok);
    assert(rootExternal.value.data.created.id == 17);

    encoded.clear();
    writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, internal.event);
    assert(error.ok);
    Deserialized!InternalEvent rootInternal;
    error = readToml(encoded.view, mallocAllocator(), &rootInternal);
    assert(error.ok);
    assert(rootInternal.value.data.deleted.id == 9);
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
    assert(encoded ==
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
            "}");

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
    assert(encoded == "{\"http_server_id\":7,\"fixed-key\":9}");

    Deserialized!CasingDocument decoded;
    JsonReadOptions readOptions;
    readOptions.keyCase = KeyCase.snake;
    error = readJson(encoded.view, mallocAllocator(), &decoded, readOptions);
    assert(error.ok);
    assert(decoded.value.httpServerID == 7);

    Writer failed = Writer.fromSink(&failingSink, null);
    error = writeJson(failed, value, options);
    assert(error.kind == SerdeErrorKind.outputFailure);

    DefaultsDocument defaults;
    StringBuf omitted = StringBuf.create(mallocAllocator());
    Writer omittedWriter = Writer.fromSink(&bufferSink, &omitted);
    error = writeJson(omittedWriter, defaults);
    assert(error.ok);
    assert(omitted == "{\"enabled\":false}");
    defaults.retryCount = 0;
    omitted.clear();
    omittedWriter = Writer.fromSink(&bufferSink, &omitted);
    error = writeJson(omittedWriter, defaults);
    assert(error.ok);
    assert(omitted == "{\"retryCount\":0,\"enabled\":false}");
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

    AllocationRecord[8] defaultRecords;
    InstrumentedAllocator defaultAllocator = InstrumentedAllocator.create(
        mallocAllocator(), defaultRecords[]);
    Deserialized!StaticInitializer initialized;
    SerdeError error = readJson("{}", defaultAllocator.handle, &initialized);
    assert(error.ok);
    assert(initialized.value.text.equal("static storage"));
    initialized.deinit();
    assert(defaultAllocator.clean);
    assert(defaultAllocator.stats.invalidCalls == 0);

    Deserialized!AlignedDocument aligned;
    error = readJson("{\"value\":7}", defaultAllocator.handle, &aligned);
    assert(error.ok);
    assert((cast(size_t) aligned.pointer & 63) == 0);
    aligned.deinit();
    assert(defaultAllocator.clean);
}

private void testJsonOptions() nothrow @nogc
{
    Deserialized!OptionalValues decoded;
    SerdeError error = readJson(
        "{\"title\":\"deploy\",\"priority\":null," ~
            "\"child\":{\"label\":\"worker\",\"value\":7}," ~
            "\"explicit_toggle\":false}",
        mallocAllocator(),
        &decoded,
    );
    assert(error.ok);
    assert(decoded.value.title.isSome);
    assert(decoded.value.title.value.equal("deploy"));
    assert(decoded.value.priority.isNone);
    assert(decoded.value.child.isSome);
    assert(decoded.value.child.value.label.equal("worker"));
    assert(decoded.value.child.value.value == 7);
    assert(decoded.value.explicitToggle.isSome);
    assert(!decoded.value.explicitToggle.value);

    // A required option requires the key, not a non-null JSON value.
    error = readJson("{\"explicit_toggle\":null}", mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.explicitToggle.isNone);
    error = readJson("{}", mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.missingRequiredField);

    OptionalValues value;
    value.title.set("release");
    value.priority.set(4);
    value.explicitToggle.set(true);
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, value);
    assert(error.ok);
    assert(encoded ==
            "{\"title\":\"release\",\"priority\":4,\"child\":null," ~
            "\"explicit_toggle\":true}");
}

private void testTomlRoundTrip() nothrow @nogc
{
    Server[2] servers = [
        Server("primary", true),
        Server("backup", false),
    ];
    TomlDocument document;
    document.applicationName = "demo";
    document.database = Database("db.local", 5432);
    document.servers = servers[];
    document.ratio = 0.125;

    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    SerdeError error = writeToml(writer, document);
    assert(error.ok);
    assert(encoded ==
            "application_name = \"demo\"\n" ~
            "database = { hostName = \"db.local\", port = 5432 }\n" ~
            "servers = [{ name = \"primary\", enabled = true }, " ~
            "{ name = \"backup\", enabled = false }]\n" ~
            "ratio = 0.125");

    Deserialized!TomlDocument decoded;
    error = readToml(encoded.view, mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.applicationName.equal("demo"));
    assert(decoded.value.database.hostName.equal("db.local"));
    assert(decoded.value.database.port == 5432);
    assert(decoded.value.servers.length == 2);
    assert(decoded.value.servers[1].name.equal("backup"));
    assert(!decoded.value.servers[1].enabled);
    assert(decoded.value.ratio == 0.125);
}

private void testTomlTablesAndSyntax() nothrow @nogc
{
    enum input =
        "# application settings\n" ~
        "application_name = 'table demo'\n" ~
        "servers = [ { name = \"one\", enabled = true }, ]\n" ~
        "ratio = +1_2.5e-1\n" ~
        "\n" ~
        "[database]\n" ~
        "hostName = \"localhost\\u002einternal\"\n" ~
        "port = 0x1538 # 5432\n";
    Deserialized!TomlDocument decoded;
    SerdeError error = readToml(input, mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.applicationName.equal("table demo"));
    assert(decoded.value.database.hostName.equal("localhost.internal"));
    assert(decoded.value.database.port == 5432);
    assert(decoded.value.servers.length == 1);
    assert(decoded.value.ratio == 1.25);

    error = readToml(
        "application_name = \"x\"\napplication_name = \"y\"\n",
        mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.duplicateField);

    error = readToml("ratio = 2026-08-01\n", mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.unsupportedValue);

    error = readToml("[[database]]\nhost_name = \"x\"\n",
        mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.unsupportedValue);

    Deserialized!OptionalDocument optional;
    error = readToml("[child]\nlabel = \"nested\"\nvalue = 17\n",
        mallocAllocator(), &optional);
    assert(error.ok);
    assert(optional.value.child !is null);
    assert(optional.value.child.label.equal("nested"));
    assert(optional.value.child.value == 17);
}

private void testTomlAllocationFailures() nothrow @nogc
{
    enum input =
        "application_name = \"allocated\"\n" ~
        "database = { hostName = \"host\", port = 1 }\n" ~
        "servers = [{ name = \"server\", enabled = true }]\n" ~
        "ratio = 1.0\n";
    bool reachedSuccess;
    foreach (allowed; 0 .. 16)
    {
        AllocationRecord[32] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        Deserialized!TomlDocument decoded;
        SerdeError error = readToml(input, allocator.handle, &decoded);
        if (error.ok)
        {
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

private void testTomlOptions() nothrow @nogc
{
    enum input =
        "title = \"deploy\"\n" ~
        "explicit_toggle = false\n" ~
        "\n" ~
        "[child]\n" ~
        "label = \"worker\"\n" ~
        "value = 7\n";
    Deserialized!OptionalValues decoded;
    SerdeError error = readToml(input, mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.title.isSome);
    assert(decoded.value.title.value.equal("deploy"));
    assert(decoded.value.priority.isNone);
    assert(decoded.value.child.isSome);
    assert(decoded.value.child.value.label.equal("worker"));
    assert(decoded.value.child.value.value == 7);
    assert(decoded.value.explicitToggle.isSome);
    assert(!decoded.value.explicitToggle.value);

    OptionalValues value;
    value.priority.set(4);
    value.explicitToggle.set(true);
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, value);
    assert(error.ok);
    assert(encoded == "priority = 4\nexplicit_toggle = true");

    error = readToml("priority = 1\n", mallocAllocator(), &decoded);
    assert(error.kind == SerdeErrorKind.missingRequiredField);
}

private void testOwnedOptionsAndFailures() nothrow @nogc
{
    enum jsonInput =
        "{\"title\":null,\"endpoint\":{\"host_name\":\"api.internal\"," ~
        "\"port\":8443,\"labels\":[\"tls\"]},\"revision\":3," ~
        "\"explicit_toggle\":true}";
    enum tomlInput =
        "title = \"scheduler\"\n" ~
        "explicit_toggle = true\n" ~
        "\n" ~
        "[endpoint]\n" ~
        "host_name = \"jobs.internal\"\n" ~
        "port = 7000\n" ~
        "labels = [\"stable\"]\n";

    AllocationRecord[128] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(), records[]);
    {
        OwnedOptionalValues value;
        SerdeError error = readJson(jsonInput, allocator.handle, &value);
        assert(error.ok);
        assert(value.title.isNone);
        assert(value.endpoint.isSome);
        assert(value.endpoint.value.hostName == "api.internal");
        assert(value.endpoint.value.labels[0] == "tls");
        assert(value.revision.value == 3);

        StringBuf title = StringBuf.fromString(allocator.handle, "release");
        value.title.set(move(title));
        value.endpoint.value.hostName.append(".test");

        StringBuf encoded = StringBuf.create(allocator.handle);
        Writer writer = Writer.fromSink(&bufferSink, &encoded);
        error = writeJson(writer, value);
        assert(error.ok);
        assert(encoded ==
                "{\"title\":\"release\",\"endpoint\":{" ~
                "\"host_name\":\"api.internal.test\",\"port\":8443," ~
                "\"labels\":[\"tls\"]},\"revision\":3," ~
                "\"explicit_toggle\":true}");

        error = readToml(tomlInput, allocator.handle, &value);
        assert(error.ok);
        assert(value.title.value == "scheduler");
        assert(value.endpoint.isSome);
        assert(value.endpoint.value.hostName == "jobs.internal");
        assert(value.endpoint.value.labels[0] == "stable");
        assert(value.revision.isNone);
    }
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);

    bool reachedSuccess;
    foreach (allowed; 0 .. 24)
    {
        AllocationRecord[128] failureRecords;
        InstrumentedAllocator failureAllocator = InstrumentedAllocator.create(
            mallocAllocator(), failureRecords[]);
        failureAllocator.failAfter(allowed);
        {
            OwnedOptionalValues value;
            SerdeError error = readJson(jsonInput, failureAllocator.handle, &value);
            if (error.ok)
                reachedSuccess = true;
            else
                assert(error.kind == SerdeErrorKind.allocationFailure);
        }
        assert(failureAllocator.clean);
        assert(failureAllocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);
}

private void testOwnedJsonRoundTripAndMutation() nothrow @nogc
{
    enum input =
        "{\"application_name\":\"control plane\"," ~
        "\"primary_endpoint\":{\"host_name\":\"api.internal\"," ~
        "\"port\":8443,\"labels\":[\"primary\",\"tls\"]}," ~
        "\"replica_endpoints\":[" ~
        "{\"host_name\":\"api-1.internal\",\"port\":8443,\"labels\":[]}," ~
        "{\"host_name\":\"api-2.internal\",\"port\":9443," ~
        "\"labels\":[\"canary\"]}]," ~
        "\"feature_flags\":[\"audit\",\"metrics\"]," ~
        "\"retry_delays\":[1,5,30],\"tracing_enabled\":true}";

    OwnedDocument document;
    SerdeError error = readJson(input, mallocAllocator(), &document);
    assert(error.ok);
    assert(document.applicationName == "control plane");
    assert(document.primaryEndpoint.hostName == "api.internal");
    assert(document.primaryEndpoint.labels.length == 2);
    assert(document.replicaEndpoints.length == 2);
    assert(document.replicaEndpoints[1].hostName == "api-2.internal");
    assert(document.featureFlags[0] == "audit");

    document.applicationName.clear();
    document.applicationName.append("edge plane");
    document.primaryEndpoint.hostName.append(".test");
    document.featureFlags[1].clear();
    document.featureFlags[1].append("telemetry");
    StringBuf addedFlag = StringBuf.fromString(mallocAllocator(), "compression");
    document.featureFlags.append(move(addedFlag));
    document.retryDelays[2] = 60;
    document.tracingEnabled = false;

    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeJson(writer, document);
    assert(error.ok);
    assert(encoded ==
            "{\"application_name\":\"edge plane\"," ~
            "\"primary_endpoint\":{\"host_name\":\"api.internal.test\"," ~
            "\"port\":8443,\"labels\":[\"primary\",\"tls\"]}," ~
            "\"replica_endpoints\":[" ~
            "{\"host_name\":\"api-1.internal\",\"port\":8443,\"labels\":[]}," ~
            "{\"host_name\":\"api-2.internal\",\"port\":9443," ~
            "\"labels\":[\"canary\"]}]," ~
            "\"feature_flags\":[\"audit\",\"telemetry\",\"compression\"]," ~
            "\"retry_delays\":[1,5,60]}");
}

private void testOwnedTomlRoundTripAndReplacement() nothrow @nogc
{
    enum first =
        "application_name = \"scheduler\"\n" ~
        "primary_endpoint = { host_name = \"jobs.internal\", port = 7000, " ~
        "labels = [\"stable\"] }\n" ~
        "replica_endpoints = [{ host_name = \"jobs-1.internal\", " ~
        "port = 7001, labels = [\"backup\"] }]\n" ~
        "feature_flags = [\"fair_queue\"]\n" ~
        "retry_delays = [2, 10, 45]\n";
    enum replacement =
        "application_name = \"worker\"\n" ~
        "primary_endpoint = { host_name = \"worker.internal\", port = 9000, " ~
        "labels = [] }\n" ~
        "replica_endpoints = []\n" ~
        "feature_flags = [\"batch\", \"priority\"]\n" ~
        "retry_delays = [1, 3, 9]\n" ~
        "tracing_enabled = true\n";

    OwnedDocument document;
    SerdeError error = readToml(first, mallocAllocator(), &document);
    assert(error.ok);
    assert(document.applicationName == "scheduler");
    assert(document.replicaEndpoints.length == 1);

    error = readToml(replacement, mallocAllocator(), &document);
    assert(error.ok);
    assert(document.applicationName == "worker");
    assert(document.primaryEndpoint.hostName == "worker.internal");
    assert(document.replicaEndpoints.empty);
    assert(document.featureFlags.length == 2);
    assert(document.tracingEnabled);

    document.featureFlags[0].append("-v2");
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, document);
    assert(error.ok);
    assert(encoded ==
            "application_name = \"worker\"\n" ~
            "primary_endpoint = { host_name = \"worker.internal\", port = 9000, " ~
            "labels = [] }\n" ~
            "replica_endpoints = []\n" ~
            "feature_flags = [\"batch-v2\", \"priority\"]\n" ~
            "retry_delays = [1, 3, 9]\n" ~
            "tracing_enabled = true");
}

private void testOwnedDecodeIsTransactional() nothrow @nogc
{
    AllocationRecord[128] records;
    InstrumentedAllocator allocator = InstrumentedAllocator.create(
        mallocAllocator(), records[]);
    OwnedDocument document;
    document.applicationName = StringBuf.fromString(allocator.handle, "preserved");

    SerdeError error = readJson(
        "{\"application_name\":\"replacement\"," ~
            "\"primary_endpoint\":{\"host_name\":\"partial\"}," ~
            "\"replica_endpoints\":[{\"host_name\":7}]}",
        allocator.handle,
        &document,
    );
    assert(error.kind == SerdeErrorKind.typeMismatch);
    assert(document.applicationName == "preserved");

    error = readToml(
        "application_name = \"replacement\"\n" ~
            "primary_endpoint = { host_name = \"partial\" }\n" ~
            "replica_endpoints = [7]\n",
        allocator.handle,
        &document,
    );
    assert(error.kind == SerdeErrorKind.typeMismatch);
    assert(document.applicationName == "preserved");

    error = readJson(
        "{\"application_name\":\"replacement succeeded\"}",
        allocator.handle,
        &document,
    );
    assert(error.ok);
    assert(document.applicationName == "replacement succeeded");
    assert(document.primaryEndpoint.hostName.allocator is allocator.handle);
    assert(document.featureFlags.allocator is allocator.handle);
    assert(document.description.allocator is allocator.handle);
    assert(document.experiments.allocator is allocator.handle);
    document.primaryEndpoint.hostName.append("initialized after decode");
    StringBuf lateFlag = StringBuf.fromString(allocator.handle, "late");
    document.featureFlags.append(move(lateFlag));
    assert(document.primaryEndpoint.hostName ==
            "initialized after decode");
    assert(document.featureFlags[0] == "late");
    destroy(document);
    assert(allocator.clean);
    assert(allocator.stats.invalidCalls == 0);
}

private void testOwnedAllocationFailures() nothrow @nogc
{
    enum input =
        "{\"application_name\":\"owned\"," ~
        "\"primary_endpoint\":{\"host_name\":\"primary\",\"labels\":[\"a\"]}," ~
        "\"replica_endpoints\":[{\"host_name\":\"replica\"," ~
        "\"labels\":[\"b\"]}],\"feature_flags\":[\"one\",\"two\"]," ~
        "\"retry_delays\":[1,2,3]}";
    bool reachedSuccess;
    foreach (allowed; 0 .. 32)
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        {
            OwnedDocument document;
            SerdeError error = readJson(input, allocator.handle, &document);
            if (error.ok)
            {
                assert(document.applicationName == "owned");
                reachedSuccess = true;
            }
            else
                assert(error.kind == SerdeErrorKind.allocationFailure);
        }
        assert(allocator.clean);
        assert(allocator.stats.invalidCalls == 0);
        if (reachedSuccess)
            break;
    }
    assert(reachedSuccess);

    enum tomlInput =
        "application_name = \"owned\"\n" ~
        "primary_endpoint = { host_name = \"primary\", labels = [\"a\"] }\n" ~
        "replica_endpoints = [{ host_name = \"replica\", labels = [\"b\"] }]\n" ~
        "feature_flags = [\"one\", \"two\"]\n" ~
        "retry_delays = [1, 2, 3]\n";
    reachedSuccess = false;
    foreach (allowed; 0 .. 32)
    {
        AllocationRecord[128] records;
        InstrumentedAllocator allocator = InstrumentedAllocator.create(
            mallocAllocator(), records[]);
        allocator.failAfter(allowed);
        {
            OwnedDocument document;
            SerdeError error = readToml(tomlInput, allocator.handle, &document);
            if (error.ok)
            {
                assert(document.applicationName == "owned");
                reachedSuccess = true;
            }
            else
                assert(error.kind == SerdeErrorKind.allocationFailure);
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
    runSerdeBackendContracts();
    testSharedPolicies();
    testJsonTaggedUnions();
    testTomlTaggedUnions();
    testJsonRoundTrip();
    testJsonPolicies();
    testJsonUnicodeAndNumbers();
    testJsonCasingAndOutputFailure();
    testJsonAllocationFailures();
    testJsonOptions();
    testTomlRoundTrip();
    testTomlTablesAndSyntax();
    testTomlAllocationFailures();
    testTomlOptions();
    testOwnedJsonRoundTripAndMutation();
    testOwnedTomlRoundTripAndReplacement();
    testOwnedDecodeIsTransactional();
    testOwnedAllocationFailures();
    testOwnedOptionsAndFailures();
    return 0;
}
