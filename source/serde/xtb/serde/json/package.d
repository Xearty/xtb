module xtb.serde.json;

nothrow @nogc:

public import xtb.serde.json.types : JsonWriteOptions, JsonReadOptions;
public import xtb.serde.json.encoder : writeJson;
public import xtb.serde.json.decoder : readJson;
