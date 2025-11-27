#ifndef _XTB_RENDERER_GEOMETRY_H_
#define _XTB_RENDERER_GEOMETRY_H_

#include <xtb_core/array.h>
#include <xtbm/xtbm.h>

typedef struct Vertex
{
    vec3 position;
    vec3 normal;
    vec2 tex_coords;
} Vertex;

typedef Array(Vertex) VertexArray;

typedef struct Mesh
{
    VertexArray vertices;
    U32Array indices;
} Mesh;

static inline Mesh geometry_create_quad(Allocator *allocator)
{
    Mesh mesh = {0};

    array_init(&mesh.vertices, allocator);
    array_reserve(&mesh.vertices, 4);

    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, 0.0f),
        .tex_coords = v2(1.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, -0.5f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, 0.0f),
        .tex_coords = v2(0.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, 0.5f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));

    array_init(&mesh.indices, allocator);
    array_reserve(&mesh.indices, 6);

    array_push(&mesh.indices, 0);
    array_push(&mesh.indices, 1);
    array_push(&mesh.indices, 3);
    array_push(&mesh.indices, 1);
    array_push(&mesh.indices, 2);
    array_push(&mesh.indices, 3);

    return mesh;
}

static inline Mesh geometry_create_cube(Allocator *allocator)
{
    Mesh mesh = {0};

    array_init(&mesh.vertices, allocator);
    array_reserve(&mesh.vertices, 36);

    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(0.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(1.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(1.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(0.0f, 0.0f),
    }));

    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(0.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(1.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(1.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(0.0f, 0.0f),
    }));

    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, 0.5f, 0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, 0.5f, -0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, 0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, 0.5f, 0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));

    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, -0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, -0.5f, -0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, -0.5f, -0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, -0.5f, 0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));

    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(1.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(0.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));

    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(1.0f, 1.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(0.0f, 0.0f),
    }));
    array_push(&mesh.vertices, ((Vertex) {
        .position = v3(-0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    }));

    return mesh;
}

#endif // _XTB_RENDERER_GEOMETRY_H_
