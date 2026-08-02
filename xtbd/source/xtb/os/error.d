module xtb.os.error;

nothrow @nogc:

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

version (linux) OsError fromErrno(int code) pure @safe
{
    import core.stdc.errno : EACCES, EAGAIN, EEXIST, EINTR, EINVAL, EISDIR,
        ECHILD, EMFILE, ENFILE, ENOENT, ENOMEM, ENOSPC, ENOTDIR, EPERM,
        EPIPE, ESRCH;

    if (code == 0)
        return OsError.init;

    OsErrorKind kind = OsErrorKind.system;
    switch (code)
    {
        case ENOENT:
        case ECHILD:
        case ESRCH:
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
        case EMFILE:
        case ENFILE:
        case ENOMEM:
        case ENOSPC:
            kind = OsErrorKind.resourceExhausted;
            break;
        case EPIPE:
            kind = OsErrorKind.brokenPipe;
            break;
        default:
            break;
    }
    return OsError(kind, code);
}

version (linux) pure @safe unittest
{
    assert(fromErrno(0).succeeded);
}

version (linux) OsError lastError() @system
{
    import core.stdc.errno : errno;

    return fromErrno(errno);
}

version (linux)
{
}
else
    OsError lastError() pure @safe
{
    return unsupported();
}
