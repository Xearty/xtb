module examples.serde_demo;

import xtb.core.memory : mallocAllocator;
import xtb.core.print : Writer, writeln;
import xtb.core.string : String, StringBuf, append;
import xtb.serde : Deserialized, KeyCase, SerdeError, fieldCase, readJson,
    readToml, required, writeJson, writeToml;

@fieldCase(KeyCase.snake)
struct ServiceConfig
{
    @required String serviceName;
    ushort port;
    bool tracingEnabled;
}

private size_t appendSink(void* context, scope String bytes) nothrow @nogc
{
    StringBuf* output = cast(StringBuf*) context;
    (*output).append(bytes);
    return bytes.length;
}

extern (C) int main()
{
    ServiceConfig config = ServiceConfig("gateway", 8080, true);

    StringBuf json = StringBuf.create(mallocAllocator());
    Writer jsonWriter = Writer.fromSink(&appendSink, &json);
    SerdeError error = writeJson(jsonWriter, config);
    if (!error.ok)
        return 1;

    StringBuf toml = StringBuf.create(mallocAllocator());
    Writer tomlWriter = Writer.fromSink(&appendSink, &toml);
    error = writeToml(tomlWriter, config);
    if (!error.ok)
        return 1;

    Deserialized!ServiceConfig decoded;
    error = readJson(json.view, mallocAllocator(), &decoded);
    if (!error.ok)
        return 1;

    writeln("JSON: ", json.view);
    writeln("TOML:\n", toml.view);
    writeln("decoded service: ", decoded.value.serviceName);

    Deserialized!ServiceConfig fromToml;
    error = readToml(toml.view, mallocAllocator(), &fromToml);
    return error.ok ? 0 : 1;
}
