#include "renderer.h"

#include "geometry.h"

#include <xtb_core/arena.h>
#include <xtb_core/thread_context.h>
#include "generated/baked_shaders_generated.h"

#include "material.cpp"
#include "polyline.cpp"
#include "bezier.cpp"
#include "camera.cpp"
#include <xtb_os/os.h>

#define STB_IMAGE_IMPLEMENTATION
#include <stb/stb_image.h>

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

    ScratchScope scratch;

    renderer->mesh_cache.quad = push_struct_zero(renderer->mesh_cache.arena, GpuMesh);
    mesh_upload(
        geometry_create_quad(&scratch->allocator),
        renderer->mesh_cache.quad
    );

    return renderer->mesh_cache.quad;
}

GpuMesh* ensure_cube_mesh(Renderer *renderer)
{
    if (renderer->mesh_cache.cube) return renderer->mesh_cache.cube;

    ScratchScope scratch;

    renderer->mesh_cache.cube = push_struct_zero(renderer->mesh_cache.arena, GpuMesh);
    mesh_upload(
        geometry_create_cube(&scratch->allocator),
        renderer->mesh_cache.cube
    );

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
    r->default_solid_color_material = Material::create_from_shader_program(&r->persistent_arena->allocator, r->shaders.mvp_solid_color);
    r->default_solid_color_material.set_vec4("color", v4(1.0f, 0.0f, 1.0f, 1.0f));
}

void init_default_textured_material(Renderer *r)
{
    r->default_textured_material = Material::create_from_shader_program(&r->persistent_arena->allocator, r->shaders.mvp_texture);
    r->default_textured_material.set_vec3("u_LightPosition", v3(20, 20, 20));
    r->default_textured_material.set_vec3("u_LightColor", v3(1, 1, 1));
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
    this->mesh_cache.models = Array<ModelEntry>::init(&this->mesh_cache.arena->allocator);

    this->shaders.test = create_shader_program("test", test_vertex_source, test_fragment_source);
    this->shaders.polyline = create_shader_program("polyline", polyline_2d_instanced_vertex_source, test_fragment_source);
    this->shaders.mvp_solid_color = create_shader_program("mvp_solid_color", mvp_vertex_source, solid_color_fragment_source);
    this->shaders.mvp_texture = create_shader_program("mvp_texture", mvp_vertex_source, texture_fragment_source);
    this->shaders.mvp_voronoi = create_shader_program("mvp_voronoi", mvp_vertex_source, voronoi_fragment_source);

    init_standard_vao(this);

    setup_polyline_render_data(this, &this->polyline_render_data);

    camera_init(&this->camera2d);
    camera_init(&this->camera3d);
    this->cameras_recreate_projections(width, height);

    init_default_solid_color_material(this);
    init_default_textured_material(this);

    this->textures = Array<TextureEntry>::init(&this->persistent_arena->allocator);
}

void Renderer::deinit()
{
    arena_release(this->mesh_cache.arena);
    arena_release(this->persistent_arena);
}

isize Renderer::find_model(String name) const
{
    for (isize i = 0; i < this->mesh_cache.models.size(); ++i)
    {
        if (this->mesh_cache.models[i].name == name)
        {
            return i;
        }
    }

    return -1;
}

isize Renderer::load_model(String name, String path)
{
    ScratchScope scratch;
    Array<Mesh> meshes = model_load(&scratch->allocator, path);

    Array<GpuMesh> gpu_meshes = Array<GpuMesh>::init_with_size(&this->mesh_cache.arena->allocator, meshes.size());
    for (isize i = 0; i < meshes.size(); ++i)
    {
        mesh_upload(meshes[i], &gpu_meshes[i]);
    }

    this->mesh_cache.models.append(ModelEntry{
        .name = name.copy(&this->mesh_cache.arena->allocator),
        .meshes = gpu_meshes,
    });

    return this->mesh_cache.models.size() - 1;
}

bool Renderer::model_loaded(String name)
{
    return this->find_model(name) != -1;
}

isize Renderer::ensure_model(String name, String path)
{
    isize model_idx = this->find_model(name);

    if (model_idx != -1)
    {
        return model_idx;
    }
    else
    {
        return this->load_model(name, path);
    }
}

isize Renderer::find_texture(String name) const
{
    for (isize i = 0; i < this->textures.size(); ++i)
    {
        if (this->textures[i].name == name)
        {
            return i;
        }
    }

    return -1;
}

isize Renderer::load_texture(String name, String path)
{
    ScratchScope scratch;

    String tex_file_data = os::read_entire_file(&scratch->allocator, path);

    i32 width, height, comp;
    // stbi_set_flip_vertically_on_load(true);
    u8* pixel_data = stbi_load_from_memory(tex_file_data.data(), tex_file_data.len(), &width, &height, &comp, 3);
    Assert(pixel_data != NULL);

    u32 tex_id;
    glCreateTextures(GL_TEXTURE_2D, 1, &tex_id);

    glBindTexture(GL_TEXTURE_2D, tex_id); // NOTE: Not sure if this is necessary.

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, pixel_data);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

    this->textures.append(TextureEntry{
        .name = name.copy(&this->mesh_cache.arena->allocator),
        .id = tex_id,
    });

    return this->textures.size() - 1;
}

bool Renderer::texture_loaded(String name)
{
    return this->find_texture(name) != -1;
}

/****************************************************************
 * Cameras
****************************************************************/
void Renderer::cameras_recreate_projections(f32 width, f32 height)
{
    mat4 ortho_proj = ortho2d_screen(width, height);
    camera_set_projection(&this->camera2d, ortho_proj);

    f32 aspect_ratio = width / height;
    mat4 perspective_proj = perspective(deg2rad(45.0f), aspect_ratio, 0.01f, 1000.0f);
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
    ScratchScope scratch;

    Material material = this->default_solid_color_material.copy(&scratch->allocator);
    material.set_vec4("color", color);

    render_mesh(this, ensure_quad_mesh(this), model, &material);
}

void Renderer::render_cube(vec4 color, mat4 model)
{
    ScratchScope scratch;

    Material material = this->default_solid_color_material.copy(&scratch->allocator);
    material.set_vec4("color", color);

    render_mesh(this, ensure_cube_mesh(this), model, &material);
}

void Renderer::render_model(String model_name, Material* material, mat4 transform)
{
    isize model_idx = this->find_model(model_name);
    Assert(model_idx != -1);

    ModelEntry* model_info = &this->mesh_cache.models[model_idx];

    for (isize i = 0; i < model_info->meshes.size(); ++i)
    {
        render_mesh(this, &model_info->meshes[i], transform, material);
    }
}

Material Renderer::create_textured_material(Allocator* allocator, String texture_name)
{
    isize texture_idx = this->find_texture(texture_name);
    Assert(texture_idx != -1);

    TextureEntry texture = this->textures[texture_idx];

    Material material = this->default_textured_material.copy(allocator);
    material.textures[0] = texture.id;
    return material;
}

Material Renderer::create_solid_color_material(Allocator* allocator, vec4 color)
{
    Material material = this->default_solid_color_material.copy(allocator);
    material.set_vec4("color", color);
    return material;
}

}

