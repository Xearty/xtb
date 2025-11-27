#ifndef _XTB_RENDERER_H_
#define _XTB_RENDERER_H_

#include "geometry.h"
#include "camera.h"
#include "xtb_core/contract.h"
#include <xtb_ogl/ogl.h>

#ifndef POLYLINE_INSTANCED_MAX_LINES
#define POLYLINE_INSTANCED_MAX_LINES 128
#endif

C_LINKAGE_BEGIN

// TODO: Use a single buffer for vertices and indices and store offsets
typedef struct GpuMesh
{
    u32 vbo;
    u32 ebo;
    Mesh *geometry;
} GpuMesh;

typedef struct GeometryCache
{
    Arena *arena;

    GpuMesh *quad;
    GpuMesh *cube;
} GeometryCache;

typedef struct ShaderRegistry
{
    ShaderProgram test;
    ShaderProgram polyline;
    ShaderProgram mvp_solid_color;
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
//
// TODO: Convert this to an enum that mirrors gl types
typedef u32 MaterialParamKind;

typedef struct MaterialParamDesc
{
    String name;
    MaterialParamKind kind;
    i32 uniform_location;
    i32 array_size;
} MaterialParamDesc;

typedef Array(MaterialParamDesc) MaterialParamDescArray;

typedef struct MaterialTemplate
{
    ShaderProgram program;
    MaterialParamDescArray params;
} MaterialTemplate;

typedef struct MaterialParamValue
{
    MaterialParamKind kind;
    union
    {
        f32 f32;
        vec2 vec2;
        vec3 vec3;
        vec4 vec4;
        mat2 mat2;
        mat3 mat3;
        mat4 mat4;
    } as;
} MaterialParamValue;

typedef Array(MaterialParamValue) MaterialParamValueArray;

typedef struct Material
{
    MaterialTemplate *templ;
    MaterialParamValueArray values;
} Material;

// TOOD: Material pool
typedef struct Renderer
{
    Arena *persistent_arena;

    GeometryCache mesh_cache;
    ShaderRegistry shaders;

    PolylineRenderData polyline_render_data;

    u32 standard_vao;

    Material default_solid_color_material;

    Camera camera2d;
    Camera camera3d;
} Renderer;

MaterialParamDescArray material_params_from_program(Allocator *allocator, ShaderProgram program);
static inline const char *gl_type_to_string(i32 type)
{
    switch (type)
    {
        case GL_FLOAT: return "float";
        case GL_FLOAT_VEC2: return "vec2";
        case GL_FLOAT_VEC3: return "vec3";
        case GL_FLOAT_VEC4: return "vec4";
        case GL_FLOAT_MAT2: return "mat2";
        case GL_FLOAT_MAT3: return "mat3";
        case GL_FLOAT_MAT4: return "mat4";
    }

    return "<Unknown>";
}

/****************************************************************
 * Renderer Lifecycle
****************************************************************/
void renderer_init(Renderer *renderer, f32 width, f32 height);
void renderer_deinit(Renderer *renderer);

/****************************************************************
 * Cameras
****************************************************************/
void renderer_cameras_recreate_projections(Renderer *renderer, f32 width, f32 height);

/****************************************************************
 * Rendering Functions
****************************************************************/
void render_quad(Renderer *renderer, vec4 color, mat4 transform);
void render_cube(Renderer *renderer, vec4 color, mat4 transform);
void render_polyline_custom(Renderer *renderer, vec2 *points, i32 count, f32 thickness, vec4 color, bool looped);
void render_bezier_spline_custom(Renderer *renderer, vec2 *points, i32 count, i32 bezier_deg, i32 samples, f32 thickness, vec4 color, bool looped);

C_LINKAGE_END

#endif // _XTB_RENDERER_H_
