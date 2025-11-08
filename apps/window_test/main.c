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

        if (window_key_is_down(XTB_KEY_SPACE))
        {
            puts("Space is down");
        }
        if (window_key_is_up(XTB_KEY_SPACE))
        {
            puts("Space is up");
        }
        if (window_key_is_pressed(XTB_KEY_SPACE))
        {
            puts("Space is pressed");
        }
        if (window_key_is_released(XTB_KEY_SPACE))
        {
            puts("Space is released");
        }

        float delta_x, delta_y;
        window_get_cursor_position(&delta_x, &delta_y);

        printf("Delta = (%f, %f)\n", delta_x, delta_y);

        window_swap_buffers(window);
    }

    window_destroy(window);

    window_system_deinit();

    return 0;
}
