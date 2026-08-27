module xtb.os.posix.signal;

nothrow @nogc:

public import core.stdc.signal : SIGABRT, SIGFPE, SIGILL, SIGSEGV, SIG_IGN;
public import core.sys.posix.signal : SA_NOCLDWAIT, SA_RESETHAND, SA_SIGINFO, SIGBUS,
    SIGCHLD, SIGKILL, SIGTERM, kill, sigaction, sigaction_t, sigemptyset,
    siginfo_t, sigset_t;
