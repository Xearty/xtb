#ifndef _XTB_RENDERER_H_
#define _XTB_RENDERER_H_

#include "geometry.h"
#include "camera.h"
#include "types.h"
#include <xtb_core/arena.h>
#include <xtb_ogl/ogl.h>
#include "generated/baked_shaders_generated.h"

#define POLYLINE_INSTANCED_MAX_LINES 128

inline Vec2Array
compute_bezier_points(Allocator *allocator, vec2 points[], size_t count, i32 samples)
{
    Assert(samples > 1);
    Assert(count > 0);

    TempArena scratch = scratch_begin_conflict(allocator);

    Vec2Array polypoints = make_array(allocator);
    array_reserve(&polypoints, samples);

    vec2 *intermediate = AllocateArray(&scratch.arena->allocator, count, vec2);

    for (int sample_iter = 0; sample_iter < samples; ++sample_iter)
    {
        float t = ilerp(0, samples - 1, sample_iter);

        float icount = count;
        memcpy(intermediate, points, sizeof(vec2) * count);

        while (icount > 1)
        {
            for (int i = 0; i < icount - 1; ++i)
            {
                intermediate[i] = lerp2(intermediate[i], intermediate[i + 1], t);
            }

            icount -= 1;
        }

        array_push(&polypoints, intermediate[0]);
    }

    scratch_end(scratch);
    return polypoints;
}

static inline Vec2Array
compute_bezier_spline_points(Allocator *allocator, vec2 *points, i32 count, i32 bezier_deg, i32 samples)
{
    Vec2Array polypoints = make_array(allocator);

    for (i32 i = 0; i < count - bezier_deg; i += bezier_deg)
    {
        Vec2Array curr_polypoints = compute_bezier_points(allocator, points + i, bezier_deg + 1, samples);

        if (i != 0)
        {
            array_append(&polypoints, curr_polypoints.data + 1, curr_polypoints.count - 1);
        }
        else
        {
            array_append(&polypoints, curr_polypoints.data, curr_polypoints.count);
        }
    }

    return polypoints;
}

typedef struct GpuMesh
{
    u32 vbo;
    u32 ebo;
    u32 vao;
    Mesh *geometry;
} GpuMesh;

typedef struct GeometryCache
{
    Arena *arena;

    GpuMesh *quad;
} GeometryCache;

typedef struct ShaderRegistry
{
    ShaderProgram test;
    ShaderProgram polyline;
} ShaderRegistry;

typedef struct PolylinePerVertexData
{
    f32 t;
    f32 side;
} PolylinePerVertexData;

typedef struct PolylineInstanceData
{
    vec2 prev;
    vec2 current_start;
    vec2 current_end;
    vec2 next;
} PolylineInstanceData;

typedef struct PolylineRenderData
{
    u32 instanced_vbo;
    u32 instanced_ebo;
    u32 vao;
    u32 per_vertex_vbo;
} PolylineRenderData;

typedef struct Renderer
{
    GeometryCache mesh_cache;
    ShaderRegistry shaders;

    PolylineRenderData polyline_render_data;

    Camera camera2d;
    Camera camera3d;
} Renderer;

static inline GpuMesh* renderer_setup_quad_data(Renderer *renderer)
{
    if (renderer->mesh_cache.quad) return renderer->mesh_cache.quad;

    renderer->mesh_cache.quad = push_struct_zero(renderer->mesh_cache.arena, GpuMesh);

    GpuMesh *quad = renderer->mesh_cache.quad;

    quad->geometry = push_struct_zero(renderer->mesh_cache.arena, Mesh);
    *quad->geometry = geometry_create_quad(&renderer->mesh_cache.arena->allocator);
    Assert(quad->geometry != NULL);

    glGenVertexArrays(1, &quad->vao);

    glGenBuffers(1, &quad->vbo);
    glBindBuffer(GL_ARRAY_BUFFER, quad->vbo);
    glBufferData(GL_ARRAY_BUFFER, quad->geometry->vertices.count * sizeof(Vertex), quad->geometry->vertices.data, GL_STATIC_DRAW);


    if (quad->geometry->indices.count > 0)
    {
        glGenBuffers(1, &quad->ebo);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, renderer->mesh_cache.quad->ebo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, quad->geometry->indices.count * sizeof(u32), quad->geometry->indices.data, GL_STATIC_DRAW);
    }

    glBindVertexArray(quad->vao);

    glBindBuffer(GL_ARRAY_BUFFER, quad->vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, quad->ebo);

    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, position));
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, tex_coords));
    glEnableVertexAttribArray(2);

    glBindVertexArray(0);

    return quad;
}

static inline void renderer_setup_polyline_data(Renderer *renderer, PolylineRenderData *out_data)
{
    PolylineRenderData *rdata = &renderer->polyline_render_data;

    glGenVertexArrays(1, &rdata->vao);
    glBindVertexArray(rdata->vao);

    glGenBuffers(1, &rdata->per_vertex_vbo);
    glGenBuffers(1, &rdata->instanced_vbo);
    glGenBuffers(1, &rdata->instanced_ebo);

    int per_vertex_stride = sizeof(PolylinePerVertexData);
    glBindBuffer(GL_ARRAY_BUFFER, rdata->per_vertex_vbo);

    glVertexAttribPointer(0, 1, GL_FLOAT, GL_FALSE, per_vertex_stride, (void *)offsetof(PolylinePerVertexData, t));
    glEnableVertexAttribArray(0);

    glVertexAttribPointer(1, 1, GL_FLOAT, GL_FALSE, per_vertex_stride, (void *)offsetof(PolylinePerVertexData, side));
    glEnableVertexAttribArray(1);

    PolylinePerVertexData per_vertex_data[] = {
        {0.0f, 1.0f},
        {1.0f, 1.0f},
        {1.0f, -1.0f},
        {0.0f, -1.0f}};

    glBufferData(GL_ARRAY_BUFFER, sizeof(per_vertex_data), per_vertex_data, GL_STATIC_DRAW);

    unsigned int indices[] = {
        0, 1, 2, //
        2, 3, 0  //
    };

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, rdata->instanced_ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);

    int instanced_stride = sizeof(PolylineInstanceData);
    glBindBuffer(GL_ARRAY_BUFFER, rdata->instanced_vbo);
    glBufferData(GL_ARRAY_BUFFER, POLYLINE_INSTANCED_MAX_LINES * instanced_stride, NULL, GL_DYNAMIC_DRAW);

    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, instanced_stride, (void *)offsetof(PolylineInstanceData, prev));
    glEnableVertexAttribArray(2);
    glVertexAttribDivisor(2, 1);

    glVertexAttribPointer(3, 2, GL_FLOAT, GL_FALSE, instanced_stride, (void *)offsetof(PolylineInstanceData, current_start));
    glEnableVertexAttribArray(3);
    glVertexAttribDivisor(3, 1);

    glVertexAttribPointer(4, 2, GL_FLOAT, GL_FALSE, instanced_stride, (void *)offsetof(PolylineInstanceData, current_end));
    glEnableVertexAttribArray(4);
    glVertexAttribDivisor(4, 1);

    glVertexAttribPointer(5, 2, GL_FLOAT, GL_FALSE, instanced_stride, (void *)offsetof(PolylineInstanceData, next));
    glEnableVertexAttribArray(5);
    glVertexAttribDivisor(5, 1);

    glBindVertexArray(0);
}

static inline void renderer_cameras_recreate_projections(Renderer *renderer, f32 width, f32 height)
{
    mat4 ortho_proj = ortho2d_screen(width, height);
    camera_set_projection(&renderer->camera2d, ortho_proj);

    f32 aspect_ratio = width / height;
    mat4 perspective_proj = perspective(deg2rad(45.0f), aspect_ratio, 0.01f, 100.0f);
    camera_set_projection(&renderer->camera3d, perspective_proj);
}

static inline void renderer_init(Renderer *renderer, f32 width, f32 height)
{
    MemoryZeroStruct(renderer);
    renderer->mesh_cache.arena = arena_new(Kilobytes(4));

    renderer->shaders.test = load_shader_program_from_memory("test", test_vertex_source, test_fragment_source);
    renderer->shaders.polyline = load_shader_program_from_memory("test", polyline_2d_instanced_vertex_source, test_fragment_source);

    renderer_setup_polyline_data(renderer, &renderer->polyline_render_data);

    camera_init(&renderer->camera2d);
    camera_init(&renderer->camera3d);
    renderer_cameras_recreate_projections(renderer, width, height);
}

static inline void render_quad(Renderer *renderer, mat4 transform)
{
    GpuMesh *quad = renderer_setup_quad_data(renderer);

    glBindVertexArray(quad->vao);
    glUseProgram(renderer->shaders.test);

    // transform = mmul4(renderer->camera.projection, mmul4(renderer->camera.view, transform));
    transform = mmul4(renderer->camera3d.projection, mmul4(renderer->camera3d.view, transform));
    u32 mvp_loc = glGetUniformLocation(renderer->shaders.test, "mvp");
    glUniformMatrix4fv(mvp_loc, 1, GL_FALSE, &transform.m00);

    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0);

    glBindVertexArray(0);
}

inline int positive_modulo(int i, int n)
{
    return (i % n + n) % n;
}

static inline void render_polyline_custom(Renderer *renderer, vec2 *points, i32 count, f32 thickness, vec4 color, bool looped)
{
    const PolylineRenderData *rdata = &renderer->polyline_render_data;

    ShaderProgram program = renderer->shaders.polyline;
    glUseProgram(program);
    glUniform1f(glGetUniformLocation(program, "uThickness"), thickness);
    glUniformMatrix4fv(glGetUniformLocation(program, "uProjection"), 1, GL_FALSE, &renderer->camera2d.projection.m00);
    glUniform4f(glGetUniformLocation(program, "color"), color.r, color.g, color.b, color.a);

    glBindVertexArray(rdata->vao);

    for (int batch_start = 0; batch_start < count - 1; batch_start += POLYLINE_INSTANCED_MAX_LINES)
    {
        PolylineInstanceData instanced_data[POLYLINE_INSTANCED_MAX_LINES] = {};

        int batch_end = min(batch_start + POLYLINE_INSTANCED_MAX_LINES, count - 1);

        for (int i = batch_start; i < batch_end; ++i)
        {
            PolylineInstanceData *inst_data = &instanced_data[i - batch_start];

            if (looped)
            {
                inst_data->prev = points[positive_modulo(i - 1, count - 1)];
                inst_data->current_start = points[i];
                inst_data->current_end = points[positive_modulo(i + 1, count - 1)];
                inst_data->next = points[positive_modulo(i + 2, count - 1)];
            }
            else
            {
                inst_data->prev = points[Max(0, i - 1)];
                inst_data->current_start = points[i];
                inst_data->current_end = points[i + 1];
                inst_data->next = points[Min(i + 2, count - 1)];
            }
        }

        int instances_in_batch = batch_end - batch_start;

        glBindBuffer(GL_ARRAY_BUFFER, rdata->instanced_vbo);
        glBufferSubData(GL_ARRAY_BUFFER, 0, instances_in_batch * sizeof(PolylineInstanceData), instanced_data);

        glDrawElementsInstanced(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0, instances_in_batch);
    }

    glBindVertexArray(0);
}

static inline void render_bezier_spline_custom(Renderer *renderer, vec2 *points, i32 count, i32 bezier_deg, i32 samples, f32 thickness, vec4 color, bool looped)
{
    TempArena scratch = scratch_begin_no_conflicts();
    Vec2Array polypoints = compute_bezier_spline_points(&scratch.arena->allocator, points, count, bezier_deg, samples);
    render_polyline_custom(renderer, polypoints.data, polypoints.count, thickness, color, looped);
    scratch_end(scratch);
}

static inline void renderer_deinit(Renderer *renderer)
{
    arena_release(renderer->mesh_cache.arena);
}

#endif // _XTB_RENDERER_H_
