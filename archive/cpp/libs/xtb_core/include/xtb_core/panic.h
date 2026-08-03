#ifndef _XTB_PANIC_H_
#define _XTB_PANIC_H_

#include <xtb_core/intrinsics.h>

namespace xtb
{

using PanicHandler = void(*)(const char* message, void* user_data);

void panic_set_handler(PanicHandler handler, void *user_data);
noreturn void panic(const char *fmt, ...);

}

#endif // _XTB_PANIC_H_
