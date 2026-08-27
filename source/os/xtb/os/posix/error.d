module xtb.os.posix.error;

nothrow @nogc:

public import core.stdc.errno : EINVAL, ENOSYS, EPERM;
import xtb.os.error : OsError, OsErrorKind;

/// Converts a POSIX errno value to XTB's low-level OS error vocabulary.
OsError fromErrno(int code) pure @safe
{
    import core.stdc.errno : EACCES, EAGAIN, ECHILD, EEXIST, EINTR, EINVAL,
        EISDIR, EMFILE, ENFILE, ENOENT, ENOMEM, ENOSPC, ENOTDIR, EPERM,
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

/// Converts the calling thread's current errno value.
OsError lastError() @system
{
    import core.stdc.errno : errno;

    return fromErrno(errno);
}

unittest
{
    assert(fromErrno(0).succeeded);
}
