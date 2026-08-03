module fuzz.utf8_fuzz;

nothrow @nogc:

import xtb.core.types : String, u8;
import xtb.core.utf8;

extern (C) int LLVMFuzzerTestOneInput(
    const(ubyte)* data,
    size_t size,
) @system
{
    const(u8)[] input = size == 0 ? null : data[0 .. size];
    const validation = validateUtf8(input);
    if (validation.failed)
        return 0;

    const checked = input.asString;
    assert(checked.succeeded);
    size_t scalarCount;
    foreach (decoded; checked.value.codePointsWithOffsets)
    {
        const encoded = encodeUtf8(decoded.value);
        const codeUnits = encoded.codeUnits;
        assert(encoded.byteLength == decoded.byteLength);
        foreach (index; 0 .. decoded.byteLength)
            assert(cast(u8) codeUnits[index] ==
                    input[decoded.byteOffset + index]);
        ++scalarCount;
    }
    assert(scalarCount == checked.value.codePointCount);

    auto reverse = checked.value.codePointsWithOffsets;
    size_t previousOffset = checked.value.length;
    while (!reverse.empty)
    {
        const decoded = reverse.back;
        assert(decoded.byteOffset + decoded.byteLength == previousOffset);
        previousOffset = decoded.byteOffset;
        reverse.popBack();
    }
    assert(previousOffset == 0);
    return 0;
}
