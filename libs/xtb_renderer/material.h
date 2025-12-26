#ifndef XTB_RENDERER_MATERIAL
#define XTB_RENDERER_MATERIAL

#include "shader.h"

#include <xtb_core/core.h>
#include <xtb_core/string.h>
#include <xtb_core/array.h>
#include <xtbm/xtbm.h>

namespace xtb
{

enum class MaterialParamKind
{
    None = 0,
    Float,
    Vec2,
    Vec3,
    Vec4,
    Mat2,
    Mat3,
    Mat4,
};

static inline const char *material_param_type_to_string(MaterialParamKind type)
{
    switch (type)
    {
        case MaterialParamKind::Float: return "float";
        case MaterialParamKind::Vec2: return "vec2";
        case MaterialParamKind::Vec3: return "vec3";
        case MaterialParamKind::Vec4: return "vec4";
        case MaterialParamKind::Mat2: return "mat2";
        case MaterialParamKind::Mat3: return "mat3";
        case MaterialParamKind::Mat4: return "mat4";
        case MaterialParamKind::None: Unreachable;
    }

    return "<Unknown>";
}

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

    static MaterialTemplate init(Allocator *allocator, ShaderProgram program);

    i32 find_param(const char *name) const;
};

struct MaterialParamValue
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
};

struct Material
{
    MaterialTemplate *templ;
    Array<MaterialParamValue> values;

    /****************************************************************
     * Index Setters
     ****************************************************************/
    void set_float_by_index(i32 index, f32 val);
    void set_vec2_by_index(i32 index, vec2 val);
    void set_vec3_by_index(i32 index, vec3 val);
    void set_vec4_by_index(i32 index, vec4 val);
    void set_mat2_by_index(i32 index, mat2 val);
    void set_mat3_by_index(i32 index, mat3 val);
    void set_mat4_by_index(i32 index, mat4 val);

    /****************************************************************
     * String Setters
     ****************************************************************/
    void set_float(const char *name, f32 val);
    void set_vec2(const char *name, vec2 val);
    void set_vec3(const char *name, vec3 val);
    void set_vec4(const char *name, vec4 val);
    void set_mat2(const char *name, mat2 val);
    void set_mat3(const char *name, mat3 val);
    void set_mat4(const char *name, mat4 val);

    /****************************************************************
     * Constructors
     ****************************************************************/
    static Material create_from_template(Allocator* allocator, MaterialTemplate* templ);
    Material copy(Allocator *allocator) const;
};

Array<MaterialParamDesc> material_params_from_program(Allocator *allocator, ShaderProgramID program);

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

}

#endif // XTB_RENDERER_MATERIAL
