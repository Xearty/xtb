module xtb.os.linux.dynamic_link;

nothrow @nogc:

public import core.sys.posix.dlfcn : Dl_info, dladdr;
