#include <xtb_window/window.h>

int main(int argc, char **argv)
{
    window_system_init();

    XTB_Window *window = window_create((XTB_Window_Config){});

    window_make_context_current(window);

    while (!window_should_close(window))
    {
        window_poll_events(window);

        window_swap_buffers(window);
    }

    window_destroy(window);

    window_system_deinit();

    return 0;
}
