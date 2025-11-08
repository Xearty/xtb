#ifndef _XTB_PANIC_H_
#define _XTB_PANIC_H_

#include <xtb_core/intrinsics.h>

XTB_C_LINKAGE_BEGIN

typedef void (*XTB_Panic_Handler)(const char *message, void *user_data);

void xtb_set_panic_handler(XTB_Panic_Handler handler, void *user_data);
XTB_NORETURN void xtb_panic(const char *fmt, ...);

XTB_C_LINKAGE_END

#endif // _XTB_PANIC_H_
