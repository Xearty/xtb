#ifndef _XTB_RENDERER_GEOMETRY_H_
#define _XTB_RENDERER_GEOMETRY_H_

#include <xtb_core/array.h>
#include <xtbm/xtbm.h>

namespace xtb
{

struct Vertex
{
    vec3 position;
    vec3 normal;
    vec2 tex_coords;
};

struct Mesh
{
    Array<Vertex> vertices;
    Array<u32> indices;
};

static inline Mesh geometry_create_quad(Allocator *allocator)
{
    Mesh mesh = {};

    mesh.vertices = Array<Vertex>::init_with_capacity(allocator, 4);

    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, 0.0f),
        .tex_coords = v2(1.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, -0.5f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, 0.0f),
        .tex_coords = v2(0.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, 0.5f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });

    mesh.indices = Array<u32>::init_with_capacity(allocator, 6);

    mesh.indices.append(0);
    mesh.indices.append(1);
    mesh.indices.append(3);
    mesh.indices.append(1);
    mesh.indices.append(2);
    mesh.indices.append(3);

    return mesh;
}

static inline Mesh geometry_create_cube(Allocator *allocator)
{
    Mesh mesh = {};

    mesh.vertices = Array<Vertex>::init_with_capacity(allocator, 36);

    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(0.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(1.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(1.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, 0.0f, -1.0f),
        .tex_coords = v2(0.0f, 0.0f),
    });

    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(0.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(1.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(1.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, 0.0f, 1.0f),
        .tex_coords = v2(0.0f, 0.0f),
    });

    mesh.vertices.append({
        .position = v3(-0.5f, 0.5f, 0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, 0.5f, -0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, 0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, 0.5f, 0.5f),
        .normal = v3(-1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });

    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, -0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, -0.5f, -0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, -0.5f, -0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, -0.5f, 0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(0.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(1.0f, 0.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });

    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(1.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, 0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(0.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, -0.5f, -0.5f),
        .normal = v3(0.0f, -1.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });

    mesh.vertices.append({
        .position = v3(-0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(1.0f, 1.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(1.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, 0.5f, 0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(0.0f, 0.0f),
    });
    mesh.vertices.append({
        .position = v3(-0.5f, 0.5f, -0.5f),
        .normal = v3(0.0f, 1.0f, 0.0f),
        .tex_coords = v2(0.0f, 1.0f),
    });

    return mesh;
}

}

#endif // _XTB_RENDERER_GEOMETRY_H_
