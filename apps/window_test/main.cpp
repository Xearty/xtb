#include "xtb_core/allocator.h"
#include <xtb_window/window.h>
#include <xtb_core/thread_context.h>
#include <xtb_ogl/ogl.h>
#include <xtb_core/string.h>
#include <xtbm/xtbm.h>
#include <xtb_renderer/renderer.h>
#include <xtb_bmp/bmp.h>
#include <xtb_renderer/types.h>

using namespace xtb;

struct WindowUserData
{
    Renderer *renderer;
};

static void framebuffer_size_callback(Window *window, i32 width, i32 height)
{
    WindowUserData *user_data = (WindowUserData*)window_user_pointer_get(window);

    glViewport(0, 0, width, height);
    user_data->renderer->cameras_recreate_projections(width, height);
}

void process_camera_movement(Window *window, Camera *camera, f32 dt)
{
    const f32 movement_speed = 20.0f * dt;

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

    const f32 mouse_sensitivity = 0.1f;

    f32 dx, dy;
    cursor_delta_get(window, &dx, &dy);
    camera_rotate_delta(camera, dx * mouse_sensitivity, -dy * mouse_sensitivity);
}

void update_global_uniforms(GlobalUniformState *uniforms)
{
    uniforms->u_Time = time_get();
}

int main(int argc, char **argv)
{
    xtb::init(argc, argv);

    window_system_init();

    ThreadContextScope tctx;

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

    Renderer renderer = Renderer::init(cfg.width, cfg.height);
    defer (renderer.deinit());

    renderer.global_uniforms_update_cb = update_global_uniforms;

    WindowUserData window_user_data = {};
    window_user_data.renderer = &renderer;

    window_user_pointer_set(window, &window_user_data);

    camera_set_position(&renderer.camera3d, v3(0.0f, 0.0f, 20.0f));
    camera_look_at(&renderer.camera3d, v3s(0.0f));

    f32 time = time_get();
    f32 prev_time = time;

    Array<MaterialParamDesc> params = material_params_from_program(allocator_get_static(), renderer.shaders.mvp_solid_color.id);

    for (i32 i = 0; i < params.size(); ++i)
    {
        MaterialParamDesc *it = &params[i];

        printf("name = \"%.*s\", ", (i32)it->name.len(), it->name.data());
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

        window_title_show_fps(window, cfg.title, dt, 0.1f);

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

        renderer.begin_frame();
        {
            glClearColor(0.1f, 0.1f, 0.1f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

            mat4 transform = I4();
            transform = uniform_scale4(transform, 5.0f);

            vec4 red = v4(1.0f, 0.0f, 0.0f, 1.0f);
            vec4 magenta = v4(1.0f, 0.0f, 1.0f, 1.0f);

            renderer.render_quad( red, transform);

            transform = translate4(transform, v3(7.0f, 0.0f, -3.0f));
            renderer.render_cube(magenta, transform);

            Array<vec2> points = Array<vec2>::init(&frame_arena->allocator);
            points.append({
                v2(100.f, 100.0f),
                v2(500.f, 1000.0f),
                v2(100.f, 800.0f),
                v2(1000.f, 500.0f),
                v2(500.f, 500.0f),
            });

            renderer.render_bezier_spline_custom(points.data(), points.size(), 2, 50, 5.0f, red, false);
        }
        renderer.end_frame();

        window_swap_buffers(window);
    }

    window_destroy(window);

    window_system_shutdown();

    return 0;
}
