#ifndef _XTB_STACKTRACE_H_
#define _XTB_STACKTRACE_H_

#include <xtb_core/context_cracking.h>

XTB_C_LINKAGE_BEGIN

void xtb_print_stack_trace(int skip_frames_count);
void xtb_print_full_stack_trace(void);

XTB_C_LINKAGE_END

#endif // _XTB_STACKTRACE_H_
