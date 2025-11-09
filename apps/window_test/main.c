#include "xtb_core/allocator.h"
#include <xtb_window/window.h>
#include <xtb_core/thread_context.h>
#include <xtb_ogl/ogl.h>
#include <xtb_core/str.h>

static void key_callback(XTB_Window *window, i32 key, i32 scancode, i32 action, i32 mods)
{
    XTB_String8 *user_pointer_str = (XTB_String8*)xtb_window_user_pointer_get(window);

    printf("pressed a key. User pointer string is \"%.*s\"\n",
            (i32)user_pointer_str->len,
            user_pointer_str->str);
}

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    xtb_window_system_init();

    Thread_Context tctx;
    tctx_init_and_equip(&tctx);

    XTB_WindowConfig cfg = xtb_window_config_default();

    XTB_Window *window = xtb_window_create(allocator_get_static(), cfg);
    if (!window)
    {
        fputs("Could not create window", stderr);
    }

    XTB_String8 user_pointer_str = xtb_str8_lit("Tova e string");

    xtb_window_set_key_callback(window, key_callback);
    xtb_window_user_pointer_set(window, &user_pointer_str);

    xtb_window_make_context_current(window);

    if (!ogl_load_gl(xtb_proc_address_get))
    {
        fputs("Could not load opengl functions\n", stderr);
        return 1;
    }

    while (!xtb_window_should_close(window))
    {
        xtb_window_poll_events(window);

        if (xtb_key_is_pressed(window, XTB_KEY_ESCAPE))
        {
            xtb_window_request_close(window);
            continue;
        }

        if (xtb_key_is_pressed(window, XTB_KEY_F))
        {
            // window_go_windowed(window);
            xtb_window_fullscreen_toggle(window);
        }

        // if (window_key_is_down(XTB_KEY_SPACE))
        // {
        //     puts("Space is down");
        // }
        // if (window_key_is_up(XTB_KEY_SPACE))
        // {
        //     puts("Space is up");
        // }
        // if (window_key_is_pressed(XTB_KEY_SPACE))
        // {
        //     puts("Space is pressed");
        // }
        // if (window_key_is_released(XTB_KEY_SPACE))
        // {
        //     puts("Space is released");
        // }
        //
        // if (window_mouse_button_is_down(XTB_MOUSE_BUTTON_LEFT))
        // {
        //     puts("Left mouse button is held down");
        // }
        //
        // if (window_mouse_button_is_released(XTB_MOUSE_BUTTON_LEFT))
        // {
        //     puts("Left mouse button was just released");
        // }

        if (xtb_cursor_entered(window))
        {
            puts("Cursor is inside window");
        }

        if (xtb_cursor_left(window))
        {
            puts("Cursor is outside window");
        }

        f32 delta_x, delta_y;
        xtb_cursor_delta_get(window, &delta_x, &delta_y);

        f32 x, y;
        xtb_cursor_pos_get(window, &x, &y);

        f32 prev_x, prev_y;
        xtb_cursor_pos_prev_get(window, &prev_x, &prev_y);

        // printf("Delta = (%f, %f) = (%f - %f, %f - %f)\n", delta_x, delta_y, x, prev_x, y, prev_y);

        xtb_window_swap_buffers(window);
    }

    xtb_window_destroy(window);

    xtb_window_system_shutdown();

    tctx_release();

    return 0;
}
