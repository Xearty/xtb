module xtb.os.error;

enum OsErrorKind : ubyte
{
    none,
    notFound,
    permissionDenied,
    alreadyExists,
    invalidArgument,
    interrupted,
    wouldBlock,
    notDirectory,
    isDirectory,
    unsupported,
    system,
}

struct OsError
{
    OsErrorKind kind;
    int nativeCode;

    bool failed() const pure nothrow @safe @nogc
    {
        return kind != OsErrorKind.none;
    }

    bool succeeded() const pure nothrow @safe @nogc
    {
        return kind == OsErrorKind.none;
    }
}

OsError unsupported() pure nothrow @safe @nogc
{
    return OsError(OsErrorKind.unsupported, 0);
}

version (linux) OsError fromErrno(int code) pure nothrow @safe @nogc
{
    import core.stdc.errno : EACCES, EAGAIN, EEXIST, EINTR, EINVAL, EISDIR,
        ENOENT, ENOTDIR, EPERM;

    OsErrorKind kind = OsErrorKind.system;
    switch (code)
    {
    case ENOENT:
        kind = OsErrorKind.notFound;
        break;
    case EACCES:
    case EPERM:
        kind = OsErrorKind.permissionDenied;
        break;
    case EEXIST:
        kind = OsErrorKind.alreadyExists;
        break;
    case EINVAL:
        kind = OsErrorKind.invalidArgument;
        break;
    case EINTR:
        kind = OsErrorKind.interrupted;
        break;
    case EAGAIN:
        kind = OsErrorKind.wouldBlock;
        break;
    case ENOTDIR:
        kind = OsErrorKind.notDirectory;
        break;
    case EISDIR:
        kind = OsErrorKind.isDirectory;
        break;
    default:
        break;
    }
    return OsError(kind, code);
}

version (linux) OsError lastError() nothrow @system @nogc
{
    import core.stdc.errno : errno;

    return fromErrno(errno);
}

version (linux)
{
}
else
    OsError lastError() pure nothrow @safe @nogc
{
    return unsupported();
}
