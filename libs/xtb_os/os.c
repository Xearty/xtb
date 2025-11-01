#include "os.h"
#include <xtb_core/platform_defines.h>

#include "libc_file.c"

#ifdef XTB_PLATFORM_UNIX
    #include "unix/file.c"
#endif
