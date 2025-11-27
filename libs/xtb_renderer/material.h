#ifndef XTB_RENDERER_MATERIAL
#define XTB_RENDERER_MATERIAL

#include <xtb_core/core.h>
#include <xtb_core/str.h>
#include <xtb_core/array.h>
#include <xtbm/xtbm.h>

typedef enum MaterialParamKind
{
    MATERIAL_PARAM_NONE = 0,
    MATERIAL_PARAM_FLOAT,
    MATERIAL_PARAM_FLOAT_VEC2,
    MATERIAL_PARAM_FLOAT_VEC3,
    MATERIAL_PARAM_FLOAT_VEC4,
    MATERIAL_PARAM_FLOAT_MAT2,
    MATERIAL_PARAM_FLOAT_MAT3,
    MATERIAL_PARAM_FLOAT_MAT4,
} MaterialParamKind;

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
    i32 program;
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

C_LINKAGE_BEGIN

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
Material material_instance_create(Allocator *allocator, MaterialTemplate *templ);
Material material_copy(Allocator *allocator, Material *m);

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

C_LINKAGE_END

#endif // XTB_RENDERER_MATERIAL
