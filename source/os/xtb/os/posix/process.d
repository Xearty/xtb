module xtb.os.posix.process;

nothrow @nogc:

public import core.sys.posix.unistd : _exit, getpid;
