#ifndef _XTB_RENDERER_H_
#define _XTB_RENDERER_H_

#include "camera.h"
#include <xtb_ogl/ogl.h>
#include "material.h"

#ifndef POLYLINE_INSTANCED_MAX_LINES
#define POLYLINE_INSTANCED_MAX_LINES 128
#endif

C_LINKAGE_BEGIN

// TODO: Use a single buffer for vertices and indices and store offsets
typedef struct GpuMesh
{
    u32 vbo;
    u32 ebo;

    u32 vertices_count;
    i32 indices_count;
} GpuMesh;

typedef struct GeometryCache
{
    Arena *arena;

    GpuMesh *quad;
    GpuMesh *cube;
} GeometryCache;

typedef struct ShaderRegistry
{
    ShaderProgramID test;
    ShaderProgramID polyline;
    ShaderProgramID mvp_solid_color;
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

MaterialParamDescArray material_params_from_program(Allocator *allocator, ShaderProgramID program);

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
