#include "renderer.h"

#include "types.h"
#include <xtb_core/arena.h>
#include <xtb_core/thread_context.h>
#include "generated/baked_shaders_generated.h"

/****************************************************************
 * Internal
****************************************************************/
static inline int positive_modulo(int i, int n)
{
    return (i % n + n) % n;
}

static Vec2Array compute_bezier_points(Allocator *allocator, vec2 points[], size_t count, i32 samples)
{
    Assert(samples > 1);
    Assert(count > 0);

    TempArena scratch = scratch_begin_conflict(allocator);

    Vec2Array polypoints = make_array(allocator);
    array_reserve(&polypoints, samples);

    vec2 *intermediate = AllocateArray(&scratch.arena->allocator, count, vec2);

    for (int sample_iter = 0; sample_iter < samples; ++sample_iter)
    {
        float t = unlerp(0, samples - 1, sample_iter);

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

static Vec2Array compute_bezier_spline_points(Allocator *allocator, vec2 *points, i32 count, i32 bezier_deg, i32 samples)
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

static void renderer_setup_polyline_data(Renderer *renderer, PolylineRenderData *out_data)
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

    int model_loc = glGetUniformLocation(program, "model");
    int view_loc = glGetUniformLocation(program, "view");
    int projection_loc = glGetUniformLocation(program, "projection");

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

// The opengl version
MaterialParamDescArray material_params_from_program(Allocator *allocator, ShaderProgram program)
{
    MaterialParamDescArray params = make_array(allocator);;

    GLint uniform_count = 0;
    glGetProgramiv(program, GL_ACTIVE_UNIFORMS, &uniform_count);

    if (uniform_count > 0)
    {
        array_reserve(&params, uniform_count);

        GLint max_name_len = 0;
        glGetProgramiv(program, GL_ACTIVE_UNIFORM_MAX_LENGTH, &max_name_len);

        TempArena scratch = scratch_begin_conflict(allocator);

        u8 *uniform_name = AllocateBytes(&scratch.arena->allocator, max_name_len + 1);

        for (GLint uniform_index = 0; uniform_index < uniform_count; ++uniform_index)
        {
            GLsizei length = 0;
            GLsizei count = 0;
            GLenum type = GL_NONE;

            glGetActiveUniform(program, uniform_index, max_name_len, &length, &count, &type, (GLchar*)uniform_name);

            MaterialParamDesc param = {};
            param.name = str_copy(allocator, str_from(uniform_name, length));
            param.kind = type;
            param.uniform_location = glGetUniformLocation(program, (GLchar*)uniform_name);
            param.array_size = count;

            array_push(&params, param);
        }

        scratch_end(scratch);
    }

    return params;
}

i32 material_find_param(const MaterialTemplate *t, const char *name)
{
    for (i32 i = 0; i < t->params.count; ++i)
    {
        MaterialParamDesc *desc = &t->params.data[i];
        if (str_eq_cstring(desc->name, name))
        {
            return i;
        }
    }

    return -1;
}

void material_set_vec4(Material *mat, const char *name, vec4 val)
{
    i32 idx = material_find_param(mat->templ, name);
    Assert(idx >= 0);
    Assert(mat->templ->params.data[idx].kind == GL_FLOAT_VEC4);

    mat->values.data[idx].kind = GL_FLOAT_VEC4;
    mat->values.data[idx].as.vec4 = val;
}

void material_set_vec2(Material *mat, const char *name, vec2 val)
{
    i32 idx = material_find_param(mat->templ, name);
    Assert(idx >= 0);
    Assert(mat->templ->params.data[idx].kind == GL_FLOAT_VEC2);

    mat->values.data[idx].kind = GL_FLOAT_VEC2;
    mat->values.data[idx].as.vec2 = val;
}

void material_set_vec3(Material *mat, const char *name, vec3 val)
{
    i32 idx = material_find_param(mat->templ, name);
    Assert(idx >= 0);
    Assert(mat->templ->params.data[idx].kind == GL_FLOAT_VEC3);

    mat->values.data[idx].kind = GL_FLOAT_VEC3;
    mat->values.data[idx].as.vec3 = val;
}

void material_set_mat4(Material *mat, const char *name, mat4 val)
{
    i32 idx = material_find_param(mat->templ, name);
    Assert(idx >= 0);
    Assert(mat->templ->params.data[idx].kind == GL_FLOAT_MAT4);

    mat->values.data[idx].kind = GL_FLOAT_MAT4;
    mat->values.data[idx].as.mat4 = val;
}

Material material_instance_create(Allocator *allocator, MaterialTemplate *templ)
{
    Material mat = {};
    mat.templ = templ;
    array_init(&mat.values, allocator);
    array_reserve(&mat.values, templ->params.count);

    return mat;
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

    renderer_setup_polyline_data(renderer, &renderer->polyline_render_data);

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

// TODO: Add support for materials
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

/****************************************************************
 * Rendering Functions
****************************************************************/
static void material_apply(Renderer *renderer, Material *material)
{
    glUseProgram(material->templ->program);

    for (i32 i = 0; i < material->templ->params.count; ++i)
    {
        const MaterialParamDesc *desc = &material->templ->params.data[i];
        const MaterialParamValue *value = &material->values.data[i];

        switch (desc->kind)
        {
            case GL_FLOAT:
            {
                glUniform1f(desc->uniform_location, value->as.f32);
            } break;

            case GL_FLOAT_VEC2:
            {
                glUniform2fv(desc->uniform_location, 1, &value->as.vec2.x);
            } break;

            case GL_FLOAT_VEC3:
            {
                glUniform3fv(desc->uniform_location, 1, &value->as.vec3.x);
            } break;

            case GL_FLOAT_VEC4:
            {
                glUniform4fv(desc->uniform_location, 1, &value->as.vec4.x);
            } break;

            case GL_FLOAT_MAT2:
            {
                glUniformMatrix2fv(desc->uniform_location, 1, GL_FALSE, &value->as.mat2.m00);
            } break;

            case GL_FLOAT_MAT3:
            {
                glUniformMatrix3fv(desc->uniform_location, 1, GL_FALSE, &value->as.mat3.m00);
            } break;

            case GL_FLOAT_MAT4:
            {
                glUniformMatrix4fv(desc->uniform_location, 1, GL_FALSE, &value->as.mat4.m00);
            } break;
        }
    }
}

Material material_copy(Material *m)
{
    Material res = {};
    res.templ = m->templ;
    array_init(&res.values, allocator_get_static());
    array_append(&res.values, m->values.data, m->values.count);
    return res;
}

static void material_set_mvp(Renderer *renderer, Material *material, mat4 model)
{
    material_set_mat4(material, "model", model);
    material_set_mat4(material, "view", renderer->camera3d.view);
    material_set_mat4(material, "projection", renderer->camera3d.projection);
}

// Implies mvp vertex shader
static void render_mesh(Renderer *renderer, GpuMesh *mesh, Material *material)
{
    material_apply(renderer, material);
    render_mesh_geometry(renderer, mesh);
}

void render_quad(Renderer *renderer, vec4 color, mat4 transform)
{
    Material material = material_copy(&renderer->default_solid_color_material);
    material_set_vec4(&material, "color", color);
    material_set_mvp(renderer, &material, transform);

    render_mesh(renderer, ensure_quad_mesh(renderer), &material);
}

void render_cube(Renderer *renderer, vec4 color, mat4 transform)
{
    Material material = material_copy(&renderer->default_solid_color_material);
    material_set_vec4(&material, "color", color); // TODO: Default is not taken into account
    material_set_mvp(renderer, &material, transform);

    render_mesh(renderer, ensure_cube_mesh(renderer), &material);
}

void render_polyline_custom(Renderer *renderer, vec2 *points, i32 count, f32 thickness, vec4 color, bool looped)
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

void render_bezier_spline_custom(Renderer *renderer, vec2 *points, i32 count, i32 bezier_deg, i32 samples, f32 thickness, vec4 color, bool looped)
{
    TempArena scratch = scratch_begin_no_conflicts();
    Vec2Array polypoints = compute_bezier_spline_points(&scratch.arena->allocator, points, count, bezier_deg, samples);
    render_polyline_custom(renderer, polypoints.data, polypoints.count, thickness, color, looped);
    scratch_end(scratch);
}
