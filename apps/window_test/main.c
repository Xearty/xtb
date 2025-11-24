#include "xtb_core/allocator.h"
#include <xtb_window/window.h>
#include <xtb_core/thread_context.h>
#include <xtb_ogl/ogl.h>
#include <xtb_core/str.h>
#include <xtbm/xtbm.h>
#include <xtb_renderer/renderer.h>
#include <xtb_bmp/bmp.h>

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
    cfg.width *= 2;

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

    glViewport(0, 0, cfg.width, cfg.height);

    Renderer renderer = {};
    renderer_init(&renderer);

    // mat4 projection2d = ortho2d(0, cfg.width, 0, cfg.height);
    mat4 projection2d = perspective(deg2rad(45.0f), (f32)cfg.width / cfg.height, 0.01f, 100.0f);

    renderer_set_projection2d(&renderer, projection2d);

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
            window_fullscreen_toggle(window);
        }

        glClearColor(0.1f, 0.1f, 0.1f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        mat4 transform = I4();
        transform = translate4(transform, v3(0.0f, 0.2f, 5.5f));
        transform = scale4(transform, mul3s(v3(0.2f, 1.2f, 1.0f), 1.0f));
        // transform = rotate4_axis(transform, v3(0, 1, 1), time_get());
        transform = rotate4_y(transform, time_get());

        mat4 inverse = affine_inverse4(transform);

        mat4 identity = mmul4(inverse, transform);

        identity = translate4(identity, v3(0.0f, 0.0f, -2.5f));

        render_quad(&renderer, identity);

        window_swap_buffers(window);
    }

    window_destroy(window);

    window_system_shutdown();

    tctx_release();

    return 0;
}
