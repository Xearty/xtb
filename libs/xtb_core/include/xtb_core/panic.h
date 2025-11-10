#ifndef _XTB_PANIC_H_
#define _XTB_PANIC_H_

#include <xtb_core/intrinsics.h>

C_LINKAGE_BEGIN

typedef void (*PanicHandler)(const char *message, void *user_data);

void panic_set_handler(PanicHandler handler, void *user_data);
noreturn void panic(const char *fmt, ...);

C_LINKAGE_END

#endif // _XTB_PANIC_H_
