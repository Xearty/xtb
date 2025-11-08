#include <xtb_window/window.h>
#include <xtb_ogl/ogl.h>

int main(int argc, char **argv)
{
    window_system_init();

    XTB_Window_Config window_config = {};
    window_config.flags |= XTB_WIN_OPENGL_CONTEXT ;

    XTB_Window *window = window_create(window_config);

    window_make_context_current(window);

    if (!ogl_load_gl(window_get_proc_address))
    {
        fputs("Could not load opengl functions\n", stderr);
        return 1;
    }

    while (!window_should_close(window))
    {
        window_poll_events(window);

        window_swap_buffers(window);
    }

    window_destroy(window);

    window_system_deinit();

    return 0;
}
