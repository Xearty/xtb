#ifndef _XTBM_H_
#define _XTBM_H_

typedef float f32;

typedef union vec2
{
    struct { f32 x, y; };
    struct { f32 s, t; };
    struct { f32 u, v; };
    f32 scalar[2];
} vec2;

typedef union vec3
{
    struct { f32 x, y, z; };
    struct { f32 r, g, b; };
    f32 scalar[3];
} vec3;

typedef union vec4
{
    struct { f32 x, y, z, w; };
    struct { f32 r, g, b, a; };
    f32 scalar[4];
} vec4;

typedef union mat2
{
    struct
    {
        f32 m00, m01;
        f32 m10, m11;
    };
    vec2 col[2];
    f32 scalar[2][2];
} mat2;

typedef union mat3
{
    struct
    {
        f32 m00, m01, m02;
        f32 m10, m11, m12;
        f32 m20, m21, m22;
    };
    vec3 col[3];
    f32 scalar[3][3];
} mat3;

typedef union mat4
{
    struct
    {
        f32 m00, m01, m02, m03;
        f32 m10, m11, m12, m13;
        f32 m20, m21, m22, m23;
        f32 m30, m31, m32, m33;
    };
    vec4 col[4];
    f32 scalar[4][4];
} mat4;


// Float vector constructor functions
static inline vec2 v2(f32 x, f32 y);
static inline vec3 v3(f32 x, f32 y, f32 z);
static inline vec4 v4(f32 x, f32 y, f32 z, f32 w);

// Matrix constructor functions
static inline mat2 M2(vec2 c0, vec2 c1);
static inline mat3 M3(vec3 c0, vec3 c1, vec3 c2);
static inline mat4 M4(vec4 c0, vec4 c1, vec4 c2, vec4 c3);

// Identity matrix constructor functions
static inline mat2 I2(void);
static inline mat3 I3(void);
static inline mat4 I4(void);

// Implementation

static inline vec2 v2(f32 x, f32 y)
{
    vec2 v;
    v.x = x;
    v.y = y;
    return v;
}

static inline vec3 v3(f32 x, f32 y, f32 z)
{
    vec3 v;
    v.x = x;
    v.y = y;
    v.z = z;
    return v;
}

static inline vec4 v4(f32 x, f32 y, f32 z, f32 w)
{
    vec4 v;
    v.x = x;
    v.y = y;
    v.z = z;
    v.w = w;
    return v;
}

static inline mat2 M2(vec2 c0, vec2 c1)
{
    mat2 m;
    m.col[0] = c0;
    m.col[1] = c1;
    return m;
}

static inline mat3 M3(vec3 c0, vec3 c1, vec3 c2)
{
    mat3 m;
    m.col[0] = c0;
    m.col[1] = c1;
    m.col[2] = c2;
    return m;
}

static inline mat4 M4(vec4 c0, vec4 c1, vec4 c2, vec4 c3)
{
    mat4 m;
    m.col[0] = c0;
    m.col[1] = c1;
    m.col[2] = c2;
    m.col[3] = c3;
    return m;
}

static inline mat2 I2(void)
{
    return M2(v2(1.0f, 0.0f), v2(0.0f, 1.0f));
}

static inline mat3 I3(void)
{
    return M3(v3(1.0f, 0.0f, 0.0f), v3(0.0f, 1.0f, 0.0f), v3(0.0f, 0.0f, 1.0f));
}

static inline mat4 I4(void)
{
    return M4(v4(1.0f, 0.0f, 0.0f, 0.0f),
              v4(0.0f, 1.0f, 0.0f, 0.0f),
              v4(0.0f, 0.0f, 1.0f, 0.0f),
              v4(0.0f, 0.0f, 0.0f, 1.0f));
}


#endif // _XTBM_H_
