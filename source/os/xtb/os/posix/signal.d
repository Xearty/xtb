module xtb.os.posix.signal;

nothrow @nogc:

public import core.stdc.signal : SIG_IGN;
public import core.sys.posix.signal : SA_NOCLDWAIT, SIGCHLD, SIGKILL, SIGTERM,
    kill, sigaction, sigaction_t, sigemptyset, sigset_t;
