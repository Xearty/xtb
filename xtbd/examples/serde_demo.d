module examples.serde_demo;

import core.lifetime : move;
import xtb.core.array : Array, append;
import xtb.core.memory : Allocator, mallocAllocator;
import xtb.core.print : Writer, writeln;
import xtb.core.string : String, StringBuf, append, clear, equal;
import xtb.serde : Deserialized, KeyCase, SerdeError, aliasName, fieldCase,
    ignore, omitDefault, readJson, readToml, rename, required, writeJson,
    writeToml;

private enum Protocol
{
    http,
    https,
}

@fieldCase(KeyCase.snake)
private struct Endpoint
{
    @required StringBuf hostName;
    ushort port;
    Protocol protocol;
    Array!StringBuf labels;
}

@fieldCase(KeyCase.snake)
private struct ServiceConfig
{
    @rename("service") @required StringBuf serviceName;
    @aliasName("primary") Endpoint primaryEndpoint;
    Array!Endpoint replicaEndpoints;
    Array!StringBuf featureFlags;
    int[3] retryDelays;
    @omitDefault bool tracingEnabled;
    @ignore uint runtimeRequests;
}

@fieldCase(KeyCase.snake)
private struct BorrowedReport
{
    @required String reportName;
    int[] samples;
}

private size_t appendSink(void* context, scope String bytes) nothrow @nogc
{
    StringBuf* output = cast(StringBuf*) context;
    (*output).append(bytes);
    return bytes.length;
}

private bool writeFormats(scope const ref ServiceConfig config) nothrow @nogc
{
    StringBuf json = StringBuf.create(mallocAllocator());
    Writer jsonWriter = Writer.fromSink(&appendSink, &json);
    SerdeError error = writeJson(jsonWriter, config);
    if (!error.ok)
        return false;

    StringBuf toml = StringBuf.create(mallocAllocator());
    Writer tomlWriter = Writer.fromSink(&appendSink, &toml);
    error = writeToml(tomlWriter, config);
    if (!error.ok)
        return false;

    writeln("mutated JSON:\n", json.view);
    writeln("mutated TOML:\n", toml.view);

    ServiceConfig fromToml;
    error = readToml(toml.view, mallocAllocator(), &fromToml);
    if (!error.ok)
        return false;
    writeln("TOML round trip: ", fromToml.serviceName.view,
        ", replicas=", fromToml.replicaEndpoints.length,
        ", flags=", fromToml.featureFlags.length);
    return true;
}

private bool demonstrateOwningDecode() nothrow @nogc
{
    enum source =
        "{\n" ~
        "  \"service\": \"gateway\",\n" ~
        "  \"primary\": {\n" ~
        "    \"host_name\": \"api.internal\",\n" ~
        "    \"port\": 8443,\n" ~
        "    \"protocol\": \"https\",\n" ~
        "    \"labels\": [\"stable\", \"regional\"]\n" ~
        "  },\n" ~
        "  \"replica_endpoints\": [\n" ~
        "    {\"host_name\": \"api-1.internal\", \"port\": 8443, " ~
        "\"protocol\": \"https\", \"labels\": [\"backup\"]}\n" ~
        "  ],\n" ~
        "  \"feature_flags\": [\"audit\", \"metrics\"],\n" ~
        "  \"retry_delays\": [1, 5, 30],\n" ~
        "  \"tracing_enabled\": true\n" ~
        "}";

    Allocator* allocator = mallocAllocator();
    ServiceConfig config;
    SerdeError error = readJson(source, allocator, &config);
    if (!error.ok)
    {
        writeln("JSON decode failed at ", error.line, ":", error.column);
        return false;
    }

    writeln("parsed service: ", config.serviceName.view);
    writeln("primary: ", config.primaryEndpoint.hostName.view,
        ":", config.primaryEndpoint.port);

    config.serviceName.clear();
    config.serviceName.append("edge-gateway");
    config.primaryEndpoint.hostName.append(".test");
    config.retryDelays[2] = 60;
    config.tracingEnabled = false;
    ++config.runtimeRequests;

    StringBuf feature = StringBuf.fromString(allocator, "compression");
    config.featureFlags.append(move(feature));

    Endpoint replica;
    replica.hostName = StringBuf.fromString(allocator, "api-2.internal");
    replica.port = 9443;
    replica.protocol = Protocol.https;
    replica.labels = Array!StringBuf.create(allocator);
    StringBuf canary = StringBuf.fromString(allocator, "canary");
    replica.labels.append(move(canary));
    config.replicaEndpoints.append(move(replica));

    if (!writeFormats(config))
        return false;

    error = readJson(
        "{\"service\":\"must not replace the current value\"," ~
            "\"primary_endpoint\":17}",
        allocator,
        &config,
    );
    if (error.ok || !config.serviceName.view.equal("edge-gateway"))
        return false;
    writeln("failed replacement preserved the parsed value at ",
        error.line, ":", error.column);
    return true;
}

private bool demonstrateDocumentOwnedDecode() nothrow @nogc
{
    Deserialized!BorrowedReport report;
    SerdeError error = readJson(
        "{\"report_name\":\"latency\",\"samples\":[12,9,15,11]}",
        mallocAllocator(),
        &report,
    );
    if (!error.ok)
        return false;

    report.value.samples[1] = 10;
    writeln("document-owned report: ", report.value.reportName,
        ", corrected sample=", report.value.samples[1]);
    return true;
}

extern (C) int main()
{
    if (!demonstrateOwningDecode())
        return 1;
    if (!demonstrateDocumentOwnedDecode())
        return 1;
    return 0;
}
