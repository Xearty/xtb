#include "xtb_core/allocator.h"
#include <xtb_window/window.h>
#include <xtb_core/thread_context.h>
#include <xtb_ogl/ogl.h>
#include <xtb_core/str.h>
#include <xtbm/xtbm.h>
#include <xtb_renderer/renderer.h>
#include <xtb_bmp/bmp.h>

typedef struct WindowUserData
{
    Renderer *renderer;
} WindowUserData;

static void key_callback(Window *window, i32 key, i32 scancode, i32 action, i32 mods)
{
    String *user_pointer_str = (String*)window_user_pointer_get(window);

    printf("pressed a key. User pointer string is \"%.*s\"\n",
            (i32)user_pointer_str->len,
            user_pointer_str->str);
}

static void framebuffer_size_callback(Window *window, i32 width, i32 height)
{
    WindowUserData *user_data = (WindowUserData*)window_user_pointer_get(window);

    glViewport(0, 0, width, height);
    renderer_cameras_recreate_projections(user_data->renderer, width, height);
}

void process_camera_movement(Window *window, Camera *camera, f32 dt)
{
    f32 movement_speed = 10.0f * dt;

    if (key_is_down(window, KEY_W))
    {
        camera_move_local(camera, v3(0.0f, 0.0f, -movement_speed));
    }

    if (key_is_down(window, KEY_S))
    {
        camera_move_local(camera, v3(0.0f, 0.0f, movement_speed));
    }

    if (key_is_down(window, KEY_A))
    {
        camera_move_local(camera, v3(-movement_speed, 0.0f, 0.0f));
    }

    if (key_is_down(window, KEY_D))
    {
        camera_move_local(camera, v3(movement_speed, 0.0f, 0.0f));
    }

    f32 dx, dy;
    cursor_delta_get(window, &dx, &dy);
    if (dx != 0.0f || dy != 0.0f)
    {
        camera->yaw += dx;
        camera->pitch -= dy;
    }
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

    window_set_key_callback(window, key_callback);
    window_set_framebuffer_size_callback(window, framebuffer_size_callback);

    cursor_capture(window);

    window_make_context_current(window);

    if (!ogl_load_gl(proc_address_get))
    {
        fputs("Could not load opengl functions\n", stderr);
        return 1;
    }

    glViewport(0, 0, cfg.width, cfg.height);

    Renderer renderer = {};
    renderer_init(&renderer, cfg.width, cfg.height);

    WindowUserData window_user_data = {};
    window_user_data.renderer = &renderer;

    window_user_pointer_set(window, &window_user_data);

    camera_set_position(&renderer.camera3d, v3(0.0f, 0.0f, 20.0f));
    camera_look_at(&renderer.camera3d, v3s(0.0f));

    f32 time = time_get();
    f32 prev_time = time;

    while (!window_should_close(window))
    {
        time = time_get();
        f32 dt = time - prev_time;
        prev_time = time;

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

        process_camera_movement(window, &renderer.camera3d, dt);
        camera_recalc_matrices(&renderer.camera3d);

        glClearColor(0.1f, 0.1f, 0.1f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        mat4 transform = I4();
        transform = uniform_scale4(transform, 5.0f);
        // transform = scale4(transform, mul3s(v3(0.2f, 1.2f, 1.0f), 1.0f));
        // transform = rotate4_y(transform, time_get());
        // transform = translate4(transform, v3(0.0f, 0.2f, 5.5f));
        // transform = rotate4_axis(transform, v3(0, 1, 1), time_get());

        // mat4 inverse = affine_inverse4(transform);

        // mat4 identity = mmul4(inverse, transform);

        // identity = translate4(identity, v3(0.0f, 0.0f, -2.5f));

        render_quad(&renderer, transform);

        window_swap_buffers(window);
    }

    window_destroy(window);

    window_system_shutdown();

    tctx_release();

    return 0;
}
