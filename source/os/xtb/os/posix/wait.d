module xtb.os.posix.wait;

nothrow @nogc:

public import core.sys.posix.sys.types : pid_t;
public import core.sys.posix.sys.wait : WNOHANG, waitpid;
