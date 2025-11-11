#ifndef _XTBM_H_
#define _XTBM_H_

typedef union vec2
{
    struct { float x, y; };
    struct { float s, t; };
    struct { float u, v; };
    float scalar[2];
} vec2;

typedef union vec3
{
    struct { float x, y, z; };
    struct { float r, g, b; };
    float scalar[3];
} vec3;

typedef union vec4
{
    struct { float x, y, z, w; };
    struct { float r, g, b, a; };
    float scalar[4];
} vec4;

typedef union mat2
{
    struct
    {
        float m00, m01;
        float m10, m11;
    };
    vec2 col[2];
    float scalar[2][2];
} mat2;

typedef union mat3
{
    struct
    {
        float m00, m01, m02;
        float m10, m11, m12;
        float m20, m21, m22;
    };
    vec3 col[3];
    float scalar[3][3];
} mat3;

typedef union mat4
{
    struct
    {
        float m00, m01, m02, m03;
        float m10, m11, m12, m13;
        float m20, m21, m22, m23;
        float m30, m31, m32, m33;
    };
    vec3 col[4];
    float scalar[4][4];
} mat4;

float lerp(float a, float b, float t);
float inverse_lerp(float a, float b, float value);

#endif // _XTBM_H_
