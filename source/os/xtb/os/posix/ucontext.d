module xtb.os.posix.ucontext;

nothrow @nogc:

public import core.sys.posix.ucontext : ucontext_t;

version (X86_64)
    public import core.sys.posix.ucontext : REG_RIP;
else version (X86)
    public import core.sys.posix.ucontext : REG_EIP;
