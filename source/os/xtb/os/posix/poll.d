module xtb.os.posix.poll;

nothrow @nogc:

public import core.sys.posix.poll : POLLIN, POLLNVAL, POLLOUT, nfds_t, pollfd;
