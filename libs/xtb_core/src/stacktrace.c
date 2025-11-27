#include <xtb_core/core.h>
#include <xtb_core/stacktrace.h>
#include <xtb_ansi/ansi.h>

#include <backtrace.h>

#include <stdint.h>
#include <stdbool.h>

typedef struct Backtrace
{
    struct backtrace_state *state;
    bool should_print_next_unknown_frame;
} Backtrace;

Backtrace g_backtrace;

void xtb_backtrace_error_callback(void *data, const char *msg, int errnum)
{
    Unused(data);
    Unused(errnum);

    ansi_print_bold_red(stderr, "BACKTRACE ERROR: %s", msg);
    fputs("\n", stderr);
}

int xtb_backtrace_full_callback(void *data,
                                 uintptr_t pc,
                                 const char *filename,
                                 int lineno,
                                 const char *function)
{
    Unused(data);
    Unused(pc);

    if (filename == NULL)
    {
        if (g_backtrace.should_print_next_unknown_frame)
        {
            ansi_print_bright_black(stderr, "    <missing debug info>");
            fputs("\n", stderr);
            g_backtrace.should_print_next_unknown_frame = false;
        }
    }
    else
    {
        // main (<path>:<lineno>)
        fputs("    ", stderr);
        ansi_print_bold_blue(stderr, "%s", function);
        fputs(" (", stderr);
        ansi_print_green(stderr, "%s", filename);
        fputs(":", stderr);
        ansi_print_red(stderr, "%d", lineno);
        fputs(")", stderr);
        fputs("\n", stderr);

        g_backtrace.should_print_next_unknown_frame = true;
    }

    return 0;
}

void print_stack_trace(int skip_frames_count)
{
    if (g_backtrace.state == NULL) return;

    g_backtrace.should_print_next_unknown_frame = true;

    fputs("Stack Trace:\n", stderr);
    backtrace_full(g_backtrace.state,
                   skip_frames_count,
                   xtb_backtrace_full_callback,
                   xtb_backtrace_error_callback,
                   NULL);
}

void print_full_stack_trace(void)
{
    print_stack_trace(0);
}

void stacktrace_init(const char *exe_path)
{
    g_backtrace.state = backtrace_create_state(exe_path, 0, xtb_backtrace_error_callback, NULL);
}
