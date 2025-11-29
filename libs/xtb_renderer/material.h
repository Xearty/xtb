#ifndef XTB_RENDERER_MATERIAL
#define XTB_RENDERER_MATERIAL

#include "shader.h"

#include <xtb_core/core.h>
#include <xtb_core/string.h>
#include <xtb_core/array.h>
#include <xtbm/xtbm.h>

namespace xtb
{

enum MaterialParamKind
{
    MATERIAL_PARAM_NONE = 0,
    MATERIAL_PARAM_FLOAT,
    MATERIAL_PARAM_FLOAT_VEC2,
    MATERIAL_PARAM_FLOAT_VEC3,
    MATERIAL_PARAM_FLOAT_VEC4,
    MATERIAL_PARAM_FLOAT_MAT2,
    MATERIAL_PARAM_FLOAT_MAT3,
    MATERIAL_PARAM_FLOAT_MAT4,
};

struct MaterialParamDesc
{
    String name;
    MaterialParamKind kind;
    i32 uniform_location;
    i32 array_size;
};

struct MaterialTemplate
{
    ShaderProgram program;
    Array<MaterialParamDesc> params;
};

typedef struct MaterialParamValue
{
    MaterialParamKind kind;
    union
    {
        f32 f32_;
        vec2 vec2_;
        vec3 vec3_;
        vec4 vec4_;
        mat2 mat2_;
        mat3 mat3_;
        mat4 mat4_;
    } as;
} MaterialParamValue;

typedef struct Material
{
    MaterialTemplate *templ;
    Array<MaterialParamValue> values;
} Material;

i32 material_find_param(const MaterialTemplate *t, const char *name);

/****************************************************************
 * Index Setters
****************************************************************/
void material_set_float_by_index(Material *mat, i32 index, f32 val);
void material_set_vec2_by_index(Material *mat, i32 index, vec2 val);
void material_set_vec3_by_index(Material *mat, i32 index, vec3 val);
void material_set_vec4_by_index(Material *mat, i32 index, vec4 val);
void material_set_mat2_by_index(Material *mat, i32 index, mat2 val);
void material_set_mat3_by_index(Material *mat, i32 index, mat3 val);
void material_set_mat4_by_index(Material *mat, i32 index, mat4 val);

/****************************************************************
 * String Setters
****************************************************************/
void material_set_float(Material *mat, const char *name, f32 val);
void material_set_vec2(Material *mat, const char *name, vec2 val);
void material_set_vec3(Material *mat, const char *name, vec3 val);
void material_set_vec4(Material *mat, const char *name, vec4 val);
void material_set_mat2(Material *mat, const char *name, mat2 val);
void material_set_mat3(Material *mat, const char *name, mat3 val);
void material_set_mat4(Material *mat, const char *name, mat4 val);

/****************************************************************
 * Constructors
****************************************************************/
void material_template_init(Allocator *allocator, ShaderProgram program, MaterialTemplate *templ);
Material material_instance_create(Allocator *allocator, MaterialTemplate *templ);
Material material_copy(Allocator *allocator, Material *m);

/****************************************************************
 * Predicates
****************************************************************/
static inline bool uniform_is_engine_global(String name)
{
    static String engine_global_uniforms[] = {
        "u_Time",
    };

    for (i32 i = 0; i < ArrLen(engine_global_uniforms); ++i)
    {
        if (name == engine_global_uniforms[i]) return true;
    }

    return false;
}

static inline bool uniform_is_mvp(String name)
{
    static String mvp_uniforms[] = {
        "model",
        "view",
        "projection",
    };

    for (i32 i = 0; i < ArrLen(mvp_uniforms); ++i)
    {
        if (name == mvp_uniforms[i]) return true;
    }

    return false;
}

static inline bool uniform_is_material_param(String name)
{
    if (uniform_is_engine_global(name)) return false;
    if (uniform_is_mvp(name))           return false;
    return true;
}

/****************************************************************
 * Miscellaneous
****************************************************************/
static inline const char *material_param_type_to_string(i32 type)
{
    switch (type)
    {
        case MATERIAL_PARAM_FLOAT: return "float";
        case MATERIAL_PARAM_FLOAT_VEC2: return "vec2";
        case MATERIAL_PARAM_FLOAT_VEC3: return "vec3";
        case MATERIAL_PARAM_FLOAT_VEC4: return "vec4";
        case MATERIAL_PARAM_FLOAT_MAT2: return "mat2";
        case MATERIAL_PARAM_FLOAT_MAT3: return "mat3";
        case MATERIAL_PARAM_FLOAT_MAT4: return "mat4";
    }

    return "<Unknown>";
}

}

#endif // XTB_RENDERER_MATERIAL
