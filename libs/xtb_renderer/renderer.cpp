#include "renderer.h"

#include "geometry.h"

#include <xtb_core/arena.h>
#include <xtb_core/thread_context.h>
#include "generated/baked_shaders_generated.h"

#include "material.cpp"
#include "polyline.cpp"
#include "bezier.cpp"
#include "camera.cpp"

namespace xtb
{

/****************************************************************
 * Internal
****************************************************************/
static void mesh_upload(Mesh mesh, GpuMesh *gpu_mesh)
{
    gpu_mesh->vertices_count = mesh.vertices.size();
    gpu_mesh->indices_count = mesh.indices.size();

    glCreateBuffers(1, &gpu_mesh->vbo);
    glNamedBufferData(
        gpu_mesh->vbo,
        mesh.vertices.size() * sizeof(Vertex),
        mesh.vertices.data(),
        GL_STATIC_DRAW
    );

    if (mesh.indices.size() > 0)
    {
        glCreateBuffers(1, &gpu_mesh->ebo);
        glNamedBufferData(
            gpu_mesh->ebo,
            mesh.indices.size() * sizeof(u32),
            mesh.indices.data(),
            GL_STATIC_DRAW
        );
    }
}

static GpuMesh* ensure_quad_mesh(Renderer *renderer)
{
    if (renderer->mesh_cache.quad) return renderer->mesh_cache.quad;

    TempArena scratch = scratch_begin_no_conflicts();

    renderer->mesh_cache.quad = push_struct_zero(renderer->mesh_cache.arena, GpuMesh);
    mesh_upload(
        geometry_create_quad(&scratch.arena->allocator),
        renderer->mesh_cache.quad
    );

    scratch_end(scratch);
    return renderer->mesh_cache.quad;
}

static GpuMesh* ensure_cube_mesh(Renderer *renderer)
{
    if (renderer->mesh_cache.cube) return renderer->mesh_cache.cube;

    TempArena scratch = scratch_begin_no_conflicts();

    renderer->mesh_cache.cube = push_struct_zero(renderer->mesh_cache.arena, GpuMesh);
    mesh_upload(
        geometry_create_cube(&scratch.arena->allocator),
        renderer->mesh_cache.cube
    );

    scratch_end(scratch);
    return renderer->mesh_cache.cube;
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
    MaterialTemplate *templ = allocate<MaterialTemplate>(&r->persistent_arena->allocator);
    material_template_init(&r->persistent_arena->allocator, r->shaders.mvp_solid_color, templ);

    r->default_solid_color_material = material_instance_create(&r->persistent_arena->allocator, templ);
    material_set_vec4(&r->default_solid_color_material, "color", v4(1.0f, 0.0f, 1.0f, 1.0f));
}

/****************************************************************
 * Renderer Lifecycle
****************************************************************/
void renderer_init(Renderer *renderer, f32 width, f32 height)
{
    *renderer = {};

    renderer->persistent_arena = arena_new(Kilobytes(4));
    renderer->mesh_cache.arena = arena_new(Kilobytes(4));

    renderer->shaders.test = create_shader_program("test", test_vertex_source, test_fragment_source);
    renderer->shaders.polyline = create_shader_program("polyline", polyline_2d_instanced_vertex_source, test_fragment_source);
    renderer->shaders.mvp_solid_color = create_shader_program("mvp_solid_color", mvp_vertex_source, solid_color_fragment_source);

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
static void set_engine_global_uniforms(Renderer *renderer, ShaderProgram program)
{
    glProgramUniform1f(program.id, program.time_location, renderer->global_uniforms.u_Time);
}

static void set_mvp_uniforms(Renderer *renderer, ShaderProgram program, mat4 model)
{
    Camera *camera3d = &renderer->camera3d;

    // NOTE: Consider the case when a uniform is not present
    glProgramUniformMatrix4fv(program.id, program.model_location, 1, GL_FALSE, &model.m00);
    glProgramUniformMatrix4fv(program.id, program.view_location, 1, GL_FALSE, &camera3d->view.m00);
    glProgramUniformMatrix4fv(program.id, program.projection_location, 1, GL_FALSE, &camera3d->projection.m00);
}

static void render_mesh_geometry(Renderer *renderer, const GpuMesh *mesh)
{
    u32 vao = renderer->standard_vao;
    glBindVertexArray(vao);
    glVertexArrayVertexBuffer(vao, 0, mesh->vbo, 0, sizeof(Vertex));

    if (mesh->indices_count > 0)
    {
        glVertexArrayElementBuffer(vao, mesh->ebo);
        glDrawElements(GL_TRIANGLES, mesh->indices_count, GL_UNSIGNED_INT, 0);
    }
    else
    {
        glDrawArrays(GL_TRIANGLES, 0, mesh->vertices_count);
    }
}

// Implies mvp vertex shader
static void render_mesh(Renderer *renderer, GpuMesh *mesh, mat4 model, Material *material)
{
    set_mvp_uniforms(renderer, material->templ->program, model);
    set_engine_global_uniforms(renderer, material->templ->program);

    material_apply(material);
    render_mesh_geometry(renderer, mesh);
}

void begin_frame(Renderer *renderer)
{
    camera_recalc_view_matrix(&renderer->camera3d);
    renderer->global_uniforms_update_cb(&renderer->global_uniforms);
}

void end_frame(Renderer *renderer)
{
}

void render_quad(Renderer *renderer, vec4 color, mat4 model)
{
    TempArena scratch = scratch_begin_no_conflicts();

    Material material = material_copy(&scratch.arena->allocator, &renderer->default_solid_color_material);
    material_set_vec4(&material, "color", color);

    render_mesh(renderer, ensure_quad_mesh(renderer), model, &material);

    scratch_end(scratch);
}

void render_cube(Renderer *renderer, vec4 color, mat4 model)
{
    TempArena scratch = scratch_begin_no_conflicts();

    Material material = material_copy(&scratch.arena->allocator, &renderer->default_solid_color_material);
    material_set_vec4(&material, "color", color);

    render_mesh(renderer, ensure_cube_mesh(renderer), model, &material);

    scratch_end(scratch);
}

}

