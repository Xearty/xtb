#ifndef _XTB_RENDERER_H_
#define _XTB_RENDERER_H_

#include "geometry.h"
#include <xtb_core/arena.h>
#include <xtb_ogl/ogl.h>
#include "generated/baked_shaders_generated.h"

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
} ShaderRegistry;

typedef struct Renderer
{
    GeometryCache mesh_cache;
    ShaderRegistry shaders;

    mat4 projection2d;
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

static inline void renderer_init(Renderer *renderer)
{
    MemoryZeroStruct(renderer);
    renderer->mesh_cache.arena = arena_new(Kilobytes(4));

    renderer->shaders.test = load_shader_program_from_memory("test", test_vertex_source, test_fragment_source);
}

static inline void renderer_set_projection2d(Renderer *renderer, mat4 projection)
{
    renderer->projection2d = projection;
}

static inline void render_quad(Renderer *renderer, mat4 transform)
{
    GpuMesh *quad = renderer_setup_quad_data(renderer);

    glBindVertexArray(quad->vao);
    glUseProgram(renderer->shaders.test);

    transform = mmul4(renderer->projection2d, transform);
    u32 mvp_loc = glGetUniformLocation(renderer->shaders.test, "mvp");
    glUniformMatrix4fv(mvp_loc, 1, GL_FALSE, &transform.m00);

    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0);

    glBindVertexArray(0);
}

static inline void renderer_deinit(Renderer *renderer)
{
    arena_release(renderer->mesh_cache.arena);
}

#endif // _XTB_RENDERER_H_
