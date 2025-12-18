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

namespace
{

/****************************************************************
 * Internal
****************************************************************/
void mesh_upload(Mesh mesh, GpuMesh *gpu_mesh)
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

GpuMesh* ensure_quad_mesh(Renderer *renderer)
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

GpuMesh* ensure_cube_mesh(Renderer *renderer)
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

void init_standard_vao(Renderer *renderer)
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
void init_default_solid_color_material(Renderer *r)
{
    MaterialTemplate *templ = allocate<MaterialTemplate>(&r->persistent_arena->allocator);
    material_template_init(&r->persistent_arena->allocator, r->shaders.mvp_solid_color, templ);

    r->default_solid_color_material = material_instance_create(&r->persistent_arena->allocator, templ);
    material_set_vec4(&r->default_solid_color_material, "color", v4(1.0f, 0.0f, 1.0f, 1.0f));
}

void set_engine_global_uniforms(Renderer *renderer, ShaderProgram program)
{
    glProgramUniform1f(program.id, program.time_location, renderer->global_uniforms.u_Time);
}

void set_mvp_uniforms(Renderer *renderer, ShaderProgram program, mat4 model)
{
    Camera *camera3d = &renderer->camera3d;

    // NOTE: Consider the case when a uniform is not present
    glProgramUniformMatrix4fv(program.id, program.model_location, 1, GL_FALSE, &model.m00);
    glProgramUniformMatrix4fv(program.id, program.view_location, 1, GL_FALSE, &camera3d->view.m00);
    glProgramUniformMatrix4fv(program.id, program.projection_location, 1, GL_FALSE, &camera3d->projection.m00);
}

void render_mesh_geometry(Renderer *renderer, const GpuMesh *mesh)
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
void render_mesh(Renderer *renderer, GpuMesh *mesh, mat4 model, Material *material)
{
    set_mvp_uniforms(renderer, material->templ->program, model);
    set_engine_global_uniforms(renderer, material->templ->program);

    material_apply(material);
    render_mesh_geometry(renderer, mesh);
}

}

/****************************************************************
 * Renderer Lifecycle
****************************************************************/
Renderer::Renderer() {}

Renderer::Renderer(f32 width, f32 height)
{
    this->persistent_arena = arena_new(Kilobytes(4));
    this->mesh_cache.arena = arena_new(Kilobytes(4));

    this->shaders.test = create_shader_program("test", test_vertex_source, test_fragment_source);
    this->shaders.polyline = create_shader_program("polyline", polyline_2d_instanced_vertex_source, test_fragment_source);
    this->shaders.mvp_solid_color = create_shader_program("mvp_solid_color", mvp_vertex_source, solid_color_fragment_source);

    init_standard_vao(this);

    setup_polyline_render_data(this, &this->polyline_render_data);

    camera_init(&this->camera2d);
    camera_init(&this->camera3d);
    this->cameras_recreate_projections(width, height);

    init_default_solid_color_material(this);
}

void Renderer::deinit()
{
    arena_release(this->mesh_cache.arena);
    arena_release(this->persistent_arena);
}

/****************************************************************
 * Cameras
****************************************************************/
void Renderer::cameras_recreate_projections(f32 width, f32 height)
{
    mat4 ortho_proj = ortho2d_screen(width, height);
    camera_set_projection(&this->camera2d, ortho_proj);

    f32 aspect_ratio = width / height;
    mat4 perspective_proj = perspective(deg2rad(45.0f), aspect_ratio, 0.01f, 100.0f);
    camera_set_projection(&this->camera3d, perspective_proj);
}

/****************************************************************
 * Rendering Functions
****************************************************************/
void Renderer::begin_frame()
{
    camera_recalc_view_matrix(&this->camera3d);
    this->global_uniforms_update_cb(&this->global_uniforms);
}

void Renderer::end_frame()
{
}

void Renderer::render_quad(vec4 color, mat4 model)
{
    TempArena scratch = scratch_begin_no_conflicts();

    Material material = material_copy(&scratch.arena->allocator, &this->default_solid_color_material);
    material_set_vec4(&material, "color", color);

    render_mesh(this, ensure_quad_mesh(this), model, &material);

    scratch_end(scratch);
}

void Renderer::render_cube(vec4 color, mat4 model)
{
    TempArena scratch = scratch_begin_no_conflicts();

    Material material = material_copy(&scratch.arena->allocator, &this->default_solid_color_material);
    material_set_vec4(&material, "color", color);

    render_mesh(this, ensure_cube_mesh(this), model, &material);

    scratch_end(scratch);
}

}

