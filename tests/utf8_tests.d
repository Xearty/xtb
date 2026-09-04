module tests.utf8_tests;

import xtb.types;
import xtb.utf8;

static assert(__traits(compiles,
    (return scope const(u8)[] input) => input.as_string,
));
static assert(__traits(compiles,
    (return scope String input) => input.code_points,
));
static assert(__traits(compiles,
    () @safe
    {
        foreach (code_point; "safe".code_points)
        {
            cast(void) code_point;
        }
    },
));

private void assert_utf8_error(
    scope const(u8)[] bytes,
    Utf8ErrorKind kind,
    usize byte_offset,
) nothrow @nogc @safe
{
    const error = validate_utf8(bytes);
    assert(error.kind == kind);
    assert(error.byte_offset == byte_offset);
}

extern (C) int main() nothrow @nogc
{
    mixin(utf8_test_body);
    return 0;
}
