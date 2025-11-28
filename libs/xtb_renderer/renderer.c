#include "renderer.h"

#include <xtb_core/arena.h>
#include <xtb_core/thread_context.h>
#include "generated/baked_shaders_generated.h"

#include "material.c"
#include "opengl_material.c"
#include "polyline.c"
#include "bezier.c"

/****************************************************************
 * Internal
****************************************************************/
static inline GpuMesh* ensure_quad_mesh(Renderer *renderer)
{
    if (renderer->mesh_cache.quad) return renderer->mesh_cache.quad;

    renderer->mesh_cache.quad = push_struct_zero(renderer->mesh_cache.arena, GpuMesh);

    GpuMesh *quad = renderer->mesh_cache.quad;

    quad->geometry = push_struct_zero(renderer->mesh_cache.arena, Mesh);
    *quad->geometry = geometry_create_quad(&renderer->mesh_cache.arena->allocator);
    Assert(quad->geometry != NULL);

    glCreateBuffers(1, &quad->vbo);
    glNamedBufferData(
        quad->vbo,
        quad->geometry->vertices.count * sizeof(Vertex),
        quad->geometry->vertices.data,
        GL_STATIC_DRAW
    );

    glCreateBuffers(1, &quad->ebo);
    glNamedBufferData(
        quad->ebo,
        quad->geometry->indices.count * sizeof(u32),
        quad->geometry->indices.data,
        GL_STATIC_DRAW
    );

    return quad;
}

static inline GpuMesh* ensure_cube_mesh(Renderer *renderer)
{
    if (renderer->mesh_cache.cube) return renderer->mesh_cache.cube;

    renderer->mesh_cache.cube = push_struct_zero(renderer->mesh_cache.arena, GpuMesh);

    GpuMesh *cube = renderer->mesh_cache.cube;

    cube->geometry = push_struct_zero(renderer->mesh_cache.arena, Mesh);
    *cube->geometry = geometry_create_cube(&renderer->mesh_cache.arena->allocator);
    Assert(cube->geometry != NULL);

    glCreateBuffers(1, &cube->vbo);
    glNamedBufferData(
        cube->vbo,
        cube->geometry->vertices.count * sizeof(Vertex),
        cube->geometry->vertices.data,
        GL_STATIC_DRAW
    );

    return cube;
}

inline void renderer_mvp_set_uniforms(const Renderer *renderer, ShaderProgram program, mat4 model)
{
    glUseProgram(program);

    i32 model_loc = glGetUniformLocation(program, "model");
    i32 view_loc = glGetUniformLocation(program, "view");
    i32 projection_loc = glGetUniformLocation(program, "projection");

    glUniformMatrix4fv(model_loc, 1, GL_FALSE, &model.m00);
    glUniformMatrix4fv(view_loc, 1, GL_FALSE, &renderer->camera3d.view.m00);
    glUniformMatrix4fv(projection_loc, 1, GL_FALSE, &renderer->camera3d.projection.m00);
}

static void init_standard_vao(Renderer *renderer)
{
    glCreateVertexArrays(1, &renderer->standard_vao);

    u32 vao = renderer->standard_vao;

    glEnableVertexArrayAttrib(vao, 0);
    glEnableVertexArrayAttrib(vao, 1);
    glEnableVertexArrayAttrib(vao, 2);

    glVertexArrayAttribBinding(vao, 0, 0);
    glVertexArrayAttribBinding(vao, 1, 0);
    glVertexArrayAttribBinding(vao, 2, 0);

    glVertexArrayAttribFormat(vao, 0, 3, GL_FLOAT, GL_FALSE, offsetof(Vertex, position));
    glVertexArrayAttribFormat(vao, 1, 3, GL_FLOAT, GL_FALSE, offsetof(Vertex, normal));
    glVertexArrayAttribFormat(vao, 2, 2, GL_FLOAT, GL_FALSE, offsetof(Vertex, tex_coords));
}
static void init_default_solid_color_material(Renderer *r)
{
    MaterialTemplate *templ = Allocate(&r->persistent_arena->allocator, MaterialTemplate);
    templ->program = r->shaders.mvp_solid_color;
    templ->params = material_params_from_program(&r->persistent_arena->allocator, templ->program);

    r->default_solid_color_material = material_instance_create(&r->persistent_arena->allocator, templ);
    material_set_vec4(&r->default_solid_color_material, "color", v4(1.0f, 0.0f, 1.0f, 1.0f));
}

/****************************************************************
 * Renderer Lifecycle
****************************************************************/
void renderer_init(Renderer *renderer, f32 width, f32 height)
{
    MemoryZeroStruct(renderer);
    renderer->persistent_arena = arena_new(Kilobytes(4));
    renderer->mesh_cache.arena = arena_new(Kilobytes(4));

    renderer->shaders.test = load_shader_program_from_memory("test", test_vertex_source, test_fragment_source);
    renderer->shaders.polyline = load_shader_program_from_memory("polyline", polyline_2d_instanced_vertex_source, test_fragment_source);
    renderer->shaders.mvp_solid_color = load_shader_program_from_memory("mvp_solid_color", mvp_vertex_source, solid_color_fragment_source);

    init_standard_vao(renderer);

    setup_polyline_render_data(renderer, &renderer->polyline_render_data);

    camera_init(&renderer->camera2d);
    camera_init(&renderer->camera3d);
    renderer_cameras_recreate_projections(renderer, width, height);

    init_default_solid_color_material(renderer);
}

void renderer_deinit(Renderer *renderer)
{
    arena_release(renderer->mesh_cache.arena);
    arena_release(renderer->persistent_arena);
}

/****************************************************************
 * Cameras
****************************************************************/
void renderer_cameras_recreate_projections(Renderer *renderer, f32 width, f32 height)
{
    mat4 ortho_proj = ortho2d_screen(width, height);
    camera_set_projection(&renderer->camera2d, ortho_proj);

    f32 aspect_ratio = width / height;
    mat4 perspective_proj = perspective(deg2rad(45.0f), aspect_ratio, 0.01f, 100.0f);
    camera_set_projection(&renderer->camera3d, perspective_proj);
}

/****************************************************************
 * Rendering Functions
****************************************************************/
static void render_mesh_geometry(Renderer *renderer, const GpuMesh *mesh)
{
    u32 vao = renderer->standard_vao;
    glBindVertexArray(vao);
    glVertexArrayVertexBuffer(vao, 0, mesh->vbo, 0, sizeof(Vertex));

    if (mesh->geometry->indices.count > 0)
    {
        glVertexArrayElementBuffer(vao, mesh->ebo);
        glDrawElements(GL_TRIANGLES, mesh->geometry->indices.count, GL_UNSIGNED_INT, 0);
    }
    else
    {
        glDrawArrays(GL_TRIANGLES, 0, mesh->geometry->vertices.count);
    }
}

// Implies mvp vertex shader
static void render_mesh(Renderer *renderer, GpuMesh *mesh, Material *material)
{
    material_apply(material);
    render_mesh_geometry(renderer, mesh);
}

static void material_set_mvp(Renderer *renderer, Material *material, mat4 model)
{
    material_set_mat4(material, "model", model);
    material_set_mat4(material, "view", renderer->camera3d.view);
    material_set_mat4(material, "projection", renderer->camera3d.projection);
}

void render_quad(Renderer *renderer, vec4 color, mat4 transform)
{
    TempArena scratch = scratch_begin_no_conflicts();

    Material material = material_copy(&scratch.arena->allocator, &renderer->default_solid_color_material);
    material_set_vec4(&material, "color", color);
    material_set_mvp(renderer, &material, transform);

    render_mesh(renderer, ensure_quad_mesh(renderer), &material);

    scratch_end(scratch);
}

void render_cube(Renderer *renderer, vec4 color, mat4 transform)
{
    TempArena scratch = scratch_begin_no_conflicts();

    Material material = material_copy(&scratch.arena->allocator, &renderer->default_solid_color_material);
    material_set_vec4(&material, "color", color);
    material_set_mvp(renderer, &material, transform);

    render_mesh(renderer, ensure_cube_mesh(renderer), &material);

    scratch_end(scratch);
}

