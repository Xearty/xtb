module xtb.os.linux.poll;

nothrow @nogc:

import xtb.os.posix.poll : nfds_t, pollfd;
import xtb.os.posix.signal : sigset_t;
public import core.sys.posix.time : timespec;

extern (C) pragma(mangle, "ppoll")
int ppoll(
    pollfd* descriptors,
    nfds_t count,
    const(timespec)* timeout,
    const(sigset_t)* signalMask,
);
