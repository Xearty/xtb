module xtb.os.linux.file;

nothrow @nogc:

import core.sys.posix.fcntl : fcntl;

/// Duplicates `descriptor` to the lowest available descriptor at or above
/// `minimum`, setting close-on-exec atomically.
int duplicateFileDescriptorCloseOnExec(int descriptor, int minimum) @system
{
    enum F_DUPFD_CLOEXEC = 1030;
    return fcntl(descriptor, F_DUPFD_CLOEXEC, minimum);
}
