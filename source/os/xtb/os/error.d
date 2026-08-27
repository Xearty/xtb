module xtb.os.error;

nothrow @nogc:

enum OsErrorKind : ubyte
{
    none,
    notFound,
    permissionDenied,
    alreadyExists,
    invalidArgument,
    invalidData,
    interrupted,
    wouldBlock,
    notDirectory,
    isDirectory,
    resourceExhausted,
    brokenPipe,
    unsupported,
    system,
}

struct OsError
{
nothrow @nogc:

    OsErrorKind kind;
    int nativeCode;

    bool failed() const pure @safe
    {
        return kind != OsErrorKind.none;
    }

    bool succeeded() const pure @safe
    {
        return kind == OsErrorKind.none;
    }
}

OsError unsupported() pure @safe
{
    return OsError(OsErrorKind.unsupported, 0);
}
