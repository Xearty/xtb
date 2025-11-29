#include "os.h"
#include <xtb_core/context_cracking.h>

#include "libc_file.cpp"

#if OS_LINUX
    #include "unix/file.cpp"
#endif
