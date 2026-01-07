#ifndef _XTB_RENDERER_GEOMETRY_H_
#define _XTB_RENDERER_GEOMETRY_H_

#include <xtb_core/array.h>
#include <xtb_core/thread_context.h>
#include <xtb_core/string.h>
#include <xtbm/xtbm.h>

#include <assimp/Importer.hpp>
#include <assimp/scene.h>
#include <assimp/postprocess.h>

#include <iostream>

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

static inline Mesh copy_mesh_data(Allocator* allocator, aiMesh* ai_mesh, bool should_flip_uv)
{
    Mesh result = {};

    std::cerr << "uv channels: " << ai_mesh->GetNumUVChannels() << "\n";

    result.vertices = Array<Vertex>::init_with_size(allocator, ai_mesh->mNumVertices);

    for (isize i = 0; i < ai_mesh->mNumVertices; ++i)
    {
        result.vertices[i].position.x = ai_mesh->mVertices[i].x;
        result.vertices[i].position.y = ai_mesh->mVertices[i].y;
        result.vertices[i].position.z = ai_mesh->mVertices[i].z;
    }

    if (ai_mesh->mNumFaces > 0)
    {
        result.indices = Array<u32>::init_with_capacity(allocator, ai_mesh->mNumFaces);

        for (isize face_idx = 0; face_idx < ai_mesh->mNumFaces; ++face_idx)
        {
            for (isize idx = 0; idx < ai_mesh->mFaces[face_idx].mNumIndices; ++idx)
            {
                result.indices.append(ai_mesh->mFaces[face_idx].mIndices[idx]);
            }
        }
    }

    if (ai_mesh->HasTextureCoords(0))
    {
        const aiVector3D* tex_coords = ai_mesh->mTextureCoords[0];

        for (isize i = 0; i < ai_mesh->mNumVertices; ++i)
        {
            if (should_flip_uv)
            {
                result.vertices[i].tex_coords.x = tex_coords[i].x;
                result.vertices[i].tex_coords.y = 1.0f - tex_coords[i].y;
            }
            else
            {
                result.vertices[i].tex_coords.x = tex_coords[i].x;
                result.vertices[i].tex_coords.y = tex_coords[i].y;
            }
        }
    }

    if (ai_mesh->HasNormals())
    {
        const aiVector3D* normals = ai_mesh->mNormals;

        for (isize i = 0; i < ai_mesh->mNumVertices; ++i)
        {
            result.vertices[i].normal.x = normals[i].x;
            result.vertices[i].normal.y = normals[i].y;
            result.vertices[i].normal.z = normals[i].z;
        }
    }

    return result;
}

static inline Array<Mesh> model_load(Allocator* allocator, String filepath)
{
    ScratchScope scratch(allocator);

    Assimp::Importer importer;

    const aiScene *scene = importer.ReadFile(
        (const char*)filepath.copy(&scratch->allocator).data(),
        aiProcess_Triangulate |
        aiProcess_CalcTangentSpace |
        aiProcess_JoinIdenticalVertices |
        aiProcess_SortByPType
    );

    Assert(scene != NULL);

    bool should_flip_uv = filepath.ends_with(".obj");

    std::cerr << "scene->mNumMeshes: " << scene->mNumMeshes << std::endl;

    Array<Mesh> model = Array<Mesh>::init_with_size(allocator, scene->mNumMeshes);

    for (isize mesh_idx = 0; mesh_idx < scene->mNumMeshes; ++mesh_idx)
    {
        model[mesh_idx] = copy_mesh_data(allocator, scene->mMeshes[mesh_idx], should_flip_uv);
    }

    return model;
}

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
