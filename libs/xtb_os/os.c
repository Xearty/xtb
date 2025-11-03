#include "os.h"
#include <xtb_core/context_cracking.h>

#include "libc_file.c"

#if XTB_OS_LINUX
    #include "unix/file.c"
#endif
