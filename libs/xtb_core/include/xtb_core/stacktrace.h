#ifndef _XTB_STACKTRACE_H_
#define _XTB_STACKTRACE_H_

#include <xtb_core/context_cracking.h>

C_LINKAGE_BEGIN

void print_stack_trace(int skip_frames_count);
void print_full_stack_trace(void);

void stacktrace_init(const char *exe_path);

C_LINKAGE_END

#endif // _XTB_STACKTRACE_H_
