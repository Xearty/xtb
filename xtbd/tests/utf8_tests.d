module tests.utf8_tests;

import xtb.core.types : String, u8;
import xtb.core.utf8;

private void assertUtf8Error(
    scope const(u8)[] bytes,
    Utf8ErrorKind kind,
    size_t byteOffset,
) nothrow @nogc @trusted
{
    const error = validateUtf8(bytes);
    assert(error.kind == kind);
    assert(error.byteOffset == byteOffset);
}

extern (C) int main() nothrow @nogc
{
    mixin(utf8TestBody);
    return 0;
}
