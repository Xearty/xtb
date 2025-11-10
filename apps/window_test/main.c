#include "xtb_core/allocator.h"
#include <xtb_window/window.h>
#include <xtb_core/thread_context.h>
#include <xtb_ogl/ogl.h>
#include <xtb_core/str.h>

static void key_callback(Window *window, i32 key, i32 scancode, i32 action, i32 mods)
{
    String *user_pointer_str = (String*)window_user_pointer_get(window);

    printf("pressed a key. User pointer string is \"%.*s\"\n",
            (i32)user_pointer_str->len,
            user_pointer_str->str);
}

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    window_system_init();

    ThreadContext tctx;
    tctx_init_and_equip(&tctx);

    WindowConfig cfg = window_config_default();

    Window *window = window_create(allocator_get_static(), cfg);
    if (!window)
    {
        fputs("Could not create window", stderr);
    }

    String user_pointer_str = str("Tova e string");

    window_set_key_callback(window, key_callback);
    window_user_pointer_set(window, &user_pointer_str);

    window_make_context_current(window);

    if (!ogl_load_gl(proc_address_get))
    {
        fputs("Could not load opengl functions\n", stderr);
        return 1;
    }

    while (!window_should_close(window))
    {
        window_poll_events(window);

        if (key_is_pressed(window, KEY_ESCAPE))
        {
            window_request_close(window);
            continue;
        }

        if (key_is_pressed(window, KEY_F))
        {
            // window_go_windowed(window);
            window_fullscreen_toggle(window);
        }

        // if (window_key_is_down(KEY_SPACE))
        // {
        //     puts("Space is down");
        // }
        // if (window_key_is_up(KEY_SPACE))
        // {
        //     puts("Space is up");
        // }
        // if (window_key_is_pressed(KEY_SPACE))
        // {
        //     puts("Space is pressed");
        // }
        // if (window_key_is_released(KEY_SPACE))
        // {
        //     puts("Space is released");
        // }
        //
        // if (window_mouse_button_is_down(MOUSE_BUTTON_LEFT))
        // {
        //     puts("Left mouse button is held down");
        // }
        //
        // if (window_mouse_button_is_released(MOUSE_BUTTON_LEFT))
        // {
        //     puts("Left mouse button was just released");
        // }

        if (cursor_entered(window))
        {
            puts("Cursor is inside window");
        }

        if (cursor_left(window))
        {
            puts("Cursor is outside window");
        }

        f32 delta_x, delta_y;
        cursor_delta_get(window, &delta_x, &delta_y);

        f32 x, y;
        cursor_pos_get(window, &x, &y);

        f32 prev_x, prev_y;
        cursor_pos_prev_get(window, &prev_x, &prev_y);

        // printf("Delta = (%f, %f) = (%f - %f, %f - %f)\n", delta_x, delta_y, x, prev_x, y, prev_y);

        window_swap_buffers(window);
    }

    window_destroy(window);

    window_system_shutdown();

    tctx_release();

    return 0;
}
