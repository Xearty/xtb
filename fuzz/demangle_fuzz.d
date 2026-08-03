module fuzz.demangle_fuzz;

nothrow @nogc:

import xtb.core.types : String;
import xtb.diagnostics.demangle : SignatureDetail, tryDemangleD;

extern (C) int LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) @system
{
    if (data is null)
        return 0;

    const input = cast(String) data[0 .. size];
    char[16 * 1024] storage;
    String output;
    static foreach (detail; [
        SignatureDetail.overloadIdentity,
        SignatureDetail.overloadIdentityAndReturn,
        SignatureDetail.full,
    ])
        tryDemangleD(input, storage[], &output, detail);
    return 0;
}
