module tests.serde_tests;

import core.lifetime : move;
import xtb.core.array : Array, append;
import xtb.core.memory : AllocationRecord, InstrumentedAllocator, mallocAllocator;
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
static assert(!__traits(compiles, validateBorrowedSchema!OwnedDocument()));
static assert(!__traits(compiles, validateOwnedSchema!Settings()));
static assert(!__traits(compiles, (ref Deserialized!Settings value) {
        Deserialized!Settings copy = value;
    }));

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
    assert(decoded.value.httpServerID == 7);

    Writer failed = Writer.fromSink(&failingSink, null);
    error = writeJson(failed, value, options);
    assert(error.kind == SerdeErrorKind.outputFailure);

    DefaultsDocument defaults;
    StringBuf omitted = StringBuf.create(mallocAllocator());
    Writer omittedWriter = Writer.fromSink(&bufferSink, &omitted);
    error = writeJson(omittedWriter, defaults);
    assert(error.ok);
    assert(omitted.view.equal("{\"enabled\":false}"));
    defaults.retryCount = 0;
    omitted.clear();
    omittedWriter = Writer.fromSink(&bufferSink, &omitted);
    error = writeJson(omittedWriter, defaults);
    assert(error.ok);
    assert(omitted.view.equal("{\"retryCount\":0,\"enabled\":false}"));
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
    assert(decoded.value.priority.empty);
    assert(decoded.value.child.isSome);
    assert(decoded.value.child.value.label.equal("worker"));
    assert(decoded.value.child.value.value == 7);
    assert(decoded.value.explicitToggle.isSome);
    assert(!decoded.value.explicitToggle.value);

    // A required option requires the key, not a non-null JSON value.
    error = readJson("{\"explicit_toggle\":null}", mallocAllocator(), &decoded);
    assert(error.ok);
    assert(decoded.value.explicitToggle.empty);
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
    assert(encoded.view.equal(
            "{\"title\":\"release\",\"priority\":4,\"child\":null," ~
            "\"explicit_toggle\":true}"));
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
    assert(encoded.view.equal(
            "application_name = \"demo\"\n" ~
            "database = { hostName = \"db.local\", port = 5432 }\n" ~
            "servers = [{ name = \"primary\", enabled = true }, " ~
            "{ name = \"backup\", enabled = false }]\n" ~
            "ratio = 0.125"));

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
    assert(decoded.value.priority.empty);
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
    assert(encoded.view.equal("priority = 4\nexplicit_toggle = true"));

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
        assert(value.title.empty);
        assert(value.endpoint.isSome);
        assert(value.endpoint.value.hostName.view.equal("api.internal"));
        assert(value.endpoint.value.labels[0].view.equal("tls"));
        assert(value.revision.value == 3);

        StringBuf title = StringBuf.fromString(allocator.handle, "release");
        value.title.set(move(title));
        value.endpoint.value.hostName.append(".test");

        StringBuf encoded = StringBuf.create(allocator.handle);
        Writer writer = Writer.fromSink(&bufferSink, &encoded);
        error = writeJson(writer, value);
        assert(error.ok);
        assert(encoded.view.equal(
                "{\"title\":\"release\",\"endpoint\":{" ~
                "\"host_name\":\"api.internal.test\",\"port\":8443," ~
                "\"labels\":[\"tls\"]},\"revision\":3," ~
                "\"explicit_toggle\":true}"));

        error = readToml(tomlInput, allocator.handle, &value);
        assert(error.ok);
        assert(value.title.value.view.equal("scheduler"));
        assert(value.endpoint.isSome);
        assert(value.endpoint.value.hostName.view.equal("jobs.internal"));
        assert(value.endpoint.value.labels[0].view.equal("stable"));
        assert(value.revision.empty);
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
    assert(document.applicationName.view.equal("control plane"));
    assert(document.primaryEndpoint.hostName.view.equal("api.internal"));
    assert(document.primaryEndpoint.labels.length == 2);
    assert(document.replicaEndpoints.length == 2);
    assert(document.replicaEndpoints[1].hostName.view.equal("api-2.internal"));
    assert(document.featureFlags[0].view.equal("audit"));

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
    assert(encoded.view.equal(
            "{\"application_name\":\"edge plane\"," ~
            "\"primary_endpoint\":{\"host_name\":\"api.internal.test\"," ~
            "\"port\":8443,\"labels\":[\"primary\",\"tls\"]}," ~
            "\"replica_endpoints\":[" ~
            "{\"host_name\":\"api-1.internal\",\"port\":8443,\"labels\":[]}," ~
            "{\"host_name\":\"api-2.internal\",\"port\":9443," ~
            "\"labels\":[\"canary\"]}]," ~
            "\"feature_flags\":[\"audit\",\"telemetry\",\"compression\"]," ~
            "\"retry_delays\":[1,5,60]}"));
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
    assert(document.applicationName.view.equal("scheduler"));
    assert(document.replicaEndpoints.length == 1);

    error = readToml(replacement, mallocAllocator(), &document);
    assert(error.ok);
    assert(document.applicationName.view.equal("worker"));
    assert(document.primaryEndpoint.hostName.view.equal("worker.internal"));
    assert(document.replicaEndpoints.empty);
    assert(document.featureFlags.length == 2);
    assert(document.tracingEnabled);

    document.featureFlags[0].append("-v2");
    StringBuf encoded = StringBuf.create(mallocAllocator());
    Writer writer = Writer.fromSink(&bufferSink, &encoded);
    error = writeToml(writer, document);
    assert(error.ok);
    assert(encoded.view.equal(
            "application_name = \"worker\"\n" ~
            "primary_endpoint = { host_name = \"worker.internal\", port = 9000, " ~
            "labels = [] }\n" ~
            "replica_endpoints = []\n" ~
            "feature_flags = [\"batch-v2\", \"priority\"]\n" ~
            "retry_delays = [1, 3, 9]\n" ~
            "tracing_enabled = true"));
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
    assert(document.applicationName.view.equal("preserved"));

    error = readToml(
        "application_name = \"replacement\"\n" ~
            "primary_endpoint = { host_name = \"partial\" }\n" ~
            "replica_endpoints = [7]\n",
        allocator.handle,
        &document,
    );
    assert(error.kind == SerdeErrorKind.typeMismatch);
    assert(document.applicationName.view.equal("preserved"));

    error = readJson(
        "{\"application_name\":\"replacement succeeded\"}",
        allocator.handle,
        &document,
    );
    assert(error.ok);
    assert(document.applicationName.view.equal("replacement succeeded"));
    assert(document.primaryEndpoint.hostName.allocator is allocator.handle);
    assert(document.featureFlags.allocator is allocator.handle);
    assert(document.description.allocator is allocator.handle);
    assert(document.experiments.allocator is allocator.handle);
    document.primaryEndpoint.hostName.append("initialized after decode");
    StringBuf lateFlag = StringBuf.fromString(allocator.handle, "late");
    document.featureFlags.append(move(lateFlag));
    assert(document.primaryEndpoint.hostName.view.equal(
            "initialized after decode"));
    assert(document.featureFlags[0].view.equal("late"));
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
                assert(document.applicationName.view.equal("owned"));
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
                assert(document.applicationName.view.equal("owned"));
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
