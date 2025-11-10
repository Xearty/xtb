#include <xtb_core/core.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

#include <xtb_core/contract.h>
#include <xtb_core/stacktrace.h>
#include <xtb_core/logger.h>

#define XTB_BACKTRACE_HANDLER_SIGNAL_LIST(MACRO)                     \
    MACRO(SIGABRT, "usually caused by an abort() or assert()")       \
    MACRO(SIGFPE, "arithmetic exception, such as divide by zero")    \
    MACRO(SIGILL, "illegal instruction")                             \
    MACRO(SIGINT, "interactive attention signal, probably a ctrl+c") \
    MACRO(SIGSEGV, "segmentation fault")                             \
    MACRO(SIGTERM, "a termination request was sent to the program")

static const char *xtb_linux_stringify_signal_description(int signal)
{
#define CASE(SIGNAL, DESC) case SIGNAL: return DESC;
    SWITCH_MACRO_ITERATOR(signal, XTB_BACKTRACE_HANDLER_SIGNAL_LIST, CASE);
    UNREACHABLE;
#undef CASE
}

static const char *xtb_linux_stringify_signal(int signal)
{
#define CASE(SIGNAL, DESC) case SIGNAL: return #SIGNAL;
    SWITCH_MACRO_ITERATOR(signal, XTB_BACKTRACE_HANDLER_SIGNAL_LIST, CASE);
    UNREACHABLE;
#undef CASE
}

static int xtb_linux_signal_exit_code(int signal)
{
    return 128 + signal;
}

static void xtb_linux_signal_handler_backtrace(int signal, siginfo_t *siginfo, void *context)
{
    XTB_LOG_FATAL("Caught %s: %s",
                  xtb_linux_stringify_signal(signal),
                  xtb_linux_stringify_signal_description(signal));

    xtb_print_full_stack_trace();
    exit(xtb_linux_signal_exit_code(signal));
}

static void register_signal_handlers(void)
{
#define REGISTER_SIGNALS(SIGNAL, DESC)                                                         \
    if (sigaction((SIGNAL), &backtrace_sigaction, NULL) < 0)                                   \
    {                                                                                          \
        xtb_panic("Registering %s signal handler failed", xtb_linux_stringify_signal(SIGNAL)); \
    }

    struct sigaction backtrace_sigaction;
    backtrace_sigaction.sa_sigaction = xtb_linux_signal_handler_backtrace;
    backtrace_sigaction.sa_flags = SA_SIGINFO;

    XTB_BACKTRACE_HANDLER_SIGNAL_LIST(REGISTER_SIGNALS);

#undef REGISTER_SIGNALS
}

#undef XTB_BACKTRACE_HANDLER_SIGNAL_LIST
