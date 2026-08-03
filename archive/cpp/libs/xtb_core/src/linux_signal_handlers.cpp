#include <xtb_core/core.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

#include <xtb_core/contract.h>
#include <xtb_core/stacktrace.h>
#include <xtb_core/logger.h>

namespace xtb
{

void panic_set_exit_code(int code);

#define BACKTRACE_HANDLER_SIGNAL_LIST(MACRO)                     \
    MACRO(SIGABRT, "usually caused by an abort() or assert()")       \
    MACRO(SIGFPE, "arithmetic exception, such as divide by zero")    \
    MACRO(SIGILL, "illegal instruction")                             \
    MACRO(SIGINT, "interactive attention signal, probably a ctrl+c") \
    MACRO(SIGSEGV, "segmentation fault")                             \
    MACRO(SIGTERM, "a termination request was sent to the program")

static const char *linux_stringify_signal_description(int signal)
{
#define CASE(SIGNAL, DESC) case SIGNAL: return DESC;
    GenSwitchMacroIterator(signal, BACKTRACE_HANDLER_SIGNAL_LIST, CASE);
    Unreachable;
#undef CASE
}

static const char *linux_stringify_signal(int signal)
{
#define CASE(SIGNAL, DESC) case SIGNAL: return #SIGNAL;
    GenSwitchMacroIterator(signal, BACKTRACE_HANDLER_SIGNAL_LIST, CASE);
    Unreachable;
#undef CASE
}

static int linux_signal_exit_code(int signal)
{
    return 128 + signal;
}

static volatile sig_atomic_t g_in_signal_handler;

static void linux_signal_handler_backtrace(int signal, siginfo_t *siginfo, void *context)
{
    Unused(siginfo);

    int exit_code = linux_signal_exit_code(signal);

    if (g_in_signal_handler)
    {
        exit(exit_code);
    }

    g_in_signal_handler = 1;

    panic_set_exit_code(exit_code);

    LOG_FATAL("Caught %s: %s",
              linux_stringify_signal(signal),
              linux_stringify_signal_description(signal));

    stacktrace::print_full();

    fflush(stdout);
    fflush(stderr);

    exit(exit_code);
}

static void register_signal_handlers(void)
{
#define REGISTER_SIGNALS(SIGNAL, DESC)                                                         \
    if (sigaction((SIGNAL), &backtrace_sigaction, NULL) < 0)                                   \
    {                                                                                          \
        panic("Registering %s signal handler failed", linux_stringify_signal(SIGNAL)); \
    }

    struct sigaction backtrace_sigaction;
    backtrace_sigaction.sa_sigaction = linux_signal_handler_backtrace;
    backtrace_sigaction.sa_flags = SA_SIGINFO;

    BACKTRACE_HANDLER_SIGNAL_LIST(REGISTER_SIGNALS);

#undef REGISTER_SIGNALS
}

#undef BACKTRACE_HANDLER_SIGNAL_LIST

}
