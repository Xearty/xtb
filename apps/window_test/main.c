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

static void framebuffer_size_callback(Window *window, i32 width, i32 height)
{
    WindowUserData *user_data = (WindowUserData*)window_user_pointer_get(window);

    glViewport(0, 0, width, height);
    renderer_cameras_recreate_projections(user_data->renderer, width, height);
}

void process_camera_movement(Window *window, Camera *camera, f32 dt)
{
    f32 movement_speed = 20.0f * dt;

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

    if (key_is_down(window, KEY_SPACE))
    {
        camera_move(camera, v3(0.0f, movement_speed, 0.0f));
    }

    if (key_is_down(window, KEY_LEFT_SHIFT))
    {
        camera_move(camera, v3(0.0f, -movement_speed, 0.0f));
    }

    f32 mouse_sensitivity = 0.5f;

    f32 dx, dy;
    cursor_delta_get(window, &dx, &dy);
    if (dx != 0.0f || dy != 0.0f)
    {
        camera->yaw += dx * mouse_sensitivity;
        camera->pitch -= dy * mouse_sensitivity;
    }
}

int main(int argc, char **argv)
{
    xtb_init(argc, argv);

    window_system_init();

    ThreadContext tctx;
    tctx_init_and_equip(&tctx);

    WindowConfig cfg = window_config_default();
    cfg.width = 2000;
    cfg.height = 1200;
    cfg.samples = 16;

    Window *window = window_create(allocator_get_static(), cfg);
    if (!window)
    {
        fputs("Could not create window", stderr);
        return 1;
    }

    window_set_framebuffer_size_callback(window, framebuffer_size_callback);

    cursor_capture(window);

    window_make_context_current(window);

    if (!ogl_load_gl(proc_address_get))
    {
        fputs("Could not load opengl functions\n", stderr);
        return 1;
    }

    glViewport(0, 0, cfg.width, cfg.height);
    glEnable(GL_DEPTH_TEST);

    Renderer renderer = {};
    renderer_init(&renderer, cfg.width, cfg.height);

    WindowUserData window_user_data = {};
    window_user_data.renderer = &renderer;

    window_user_pointer_set(window, &window_user_data);

    camera_set_position(&renderer.camera3d, v3(0.0f, 0.0f, 20.0f));
    camera_look_at(&renderer.camera3d, v3s(0.0f));

    f32 time = time_get();
    f32 prev_time = time;

    MaterialParamDescArray params = material_params_from_program(allocator_get_static(), renderer.shaders.mvp_solid_color);

    for (i32 i = 0; i < params.count; ++i)
    {
        MaterialParamDesc *it = &params.data[i];

        printf("name = \"%.*s\", ", (i32)it->name.len, it->name.str);
        printf("kind = \"%s\", ", material_param_type_to_string(it->kind));
        printf("uniform_location = %d, ", it->uniform_location);
        printf("array_size = %d\n", it->array_size);
    }

    Arena *frame_arena = arena_new(Kilobytes(4));

    while (!window_should_close(window))
    {
        arena_clear(frame_arena);

        time = time_get();
        f32 dt = time - prev_time;
        prev_time = time;

        window_poll_events(window);

        if (key_is_pressed(window, KEY_Q))
        {
            toggle_wireframe();
        }

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
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        mat4 transform = I4();
        transform = uniform_scale4(transform, 5.0f);
        // transform = scale4(transform, mul3s(v3(0.2f, 1.2f, 1.0f), 1.0f));
        // transform = rotate4_y(transform, time_get());
        // transform = translate4(transform, v3(0.0f, 0.2f, 5.5f));
        // transform = rotate4_axis(transform, v3(0, 1, 1), time_get());

        // mat4 inverse = affine_inverse4(transform);

        // mat4 identity = mmul4(inverse, transform);

        // identity = translate4(identity, v3(0.0f, 0.0f, -2.5f));

        vec4 red = v4(1.0f, 0.0f, 0.0f, 1.0f);
        vec4 magenta = v4(1.0f, 0.0f, 1.0f, 1.0f);

        render_quad(&renderer, red, transform);

        transform = translate4(transform, v3(7.0f, 0.0f, -3.0f));
        render_cube(&renderer, magenta, transform);

        Vec2Array points = make_array(&frame_arena->allocator);
        array_push(&points, v2(100.f, 100.0f));
        array_push(&points, v2(500.f, 1000.0f));
        array_push(&points, v2(100.f, 800.0f));
        array_push(&points, v2(1000.f, 500.0f));
        array_push(&points, v2(500.f, 500.0f));

        render_bezier_spline_custom(&renderer, points.data, points.count, 2, 50, 5.0f, red, false);

        window_swap_buffers(window);
    }

    window_destroy(window);

    window_system_shutdown();

    tctx_release();

    return 0;
}
