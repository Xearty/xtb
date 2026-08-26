module xtb.cli.value;

nothrow @nogc:

import xtb.types : String;

/// Result returned by application-defined CLI value parsers.
enum CliValueErrorKind : ubyte
{
    none,
    invalid,
    outOfRange,
    allocationFailed,
}

/// Borrowed diagnostic returned by a custom CLI value parser.
///
/// `message` is optional. When non-empty, its backing storage must remain valid
/// until the containing `CliParseResult` is deinitialized. String literals and
/// other suitably long-lived borrowed strings are therefore appropriate.
struct CliValueError
{
nothrow @nogc:

    CliValueErrorKind kind;
    String message;

    static CliValueError invalid(return scope String message = null) pure @safe
    {
        return CliValueError(CliValueErrorKind.invalid, message);
    }

    static CliValueError outOfRange(return scope String message = null) pure @safe
    {
        return CliValueError(CliValueErrorKind.outOfRange, message);
    }

    static CliValueError allocationFailed(return scope String message = null) pure @safe
    {
        return CliValueError(CliValueErrorKind.allocationFailed, message);
    }

    bool failed() const pure @safe
    {
        return kind != CliValueErrorKind.none;
    }
}
