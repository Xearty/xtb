#ifndef _XTBM_H_
#define _XTBM_H_

#include <math.h>

#define PI 3.14159265359f
#define E 2.71828f
#define GOLDEN_RATIO 1.61803398875f

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

// Scalar fill
static inline vec2 v2s(f32 s);
static inline vec3 v3s(f32 s);
static inline vec4 v4s(f32 s);

// Extending constructors
static inline vec3 v3v2(vec2 xy, f32 z);
static inline vec4 v4v3(vec3 xyz, f32 w);
static inline vec4 v4v2(vec2 xy, f32 z, f32 w);

// Truncating constructors
static inline vec2 v2v3(vec3 v);
static inline vec2 v2v4(vec4 v);
static inline vec3 v3v4(vec4 v);

// Vector arithmetic
static inline vec2 add2(vec2 a, vec2 b);
static inline vec3 add3(vec3 a, vec3 b);
static inline vec4 add4(vec4 a, vec4 b);

static inline vec2 sub2(vec2 a, vec2 b);
static inline vec3 sub3(vec3 a, vec3 b);
static inline vec4 sub4(vec4 a, vec4 b);

static inline vec2 mul2(vec2 a, vec2 b);
static inline vec3 mul3(vec3 a, vec3 b);
static inline vec4 mul4(vec4 a, vec4 b);

static inline vec2 div2(vec2 a, vec2 b);
static inline vec3 div3(vec3 a, vec3 b);
static inline vec4 div4(vec4 a, vec4 b);

static inline vec2 add2s(vec2 a, f32 s);
static inline vec3 add3s(vec3 a, f32 s);
static inline vec4 add4s(vec4 a, f32 s);

static inline vec2 sub2s(vec2 a, f32 s);
static inline vec3 sub3s(vec3 a, f32 s);
static inline vec4 sub4s(vec4 a, f32 s);

static inline vec2 mul2s(vec2 a, f32 s);
static inline vec3 mul3s(vec3 a, f32 s);
static inline vec4 mul4s(vec4 a, f32 s);

static inline vec2 div2s(vec2 a, f32 s);
static inline vec3 div3s(vec3 a, f32 s);
static inline vec4 div4s(vec4 a, f32 s);

// Vector products
static inline f32 dot2(vec2 a, vec2 b);
static inline f32 dot3(vec3 a, vec3 b);
static inline f32 dot4(vec4 a, vec4 b);

static inline vec3 cross(vec3 a, vec3 b);

// Vector length squared
static inline f32 lensq2(vec2 a);
static inline f32 lensq3(vec3 a);
static inline f32 lensq4(vec4 a);

// Vector length
static inline f32 len2(vec2 a);
static inline f32 len3(vec3 a);
static inline f32 len4(vec4 a);

// Vector normalization
static inline vec2 norm2(vec2 a);
static inline vec3 norm3(vec3 a);
static inline vec4 norm4(vec4 a);

// Distance
static inline f32 distsq2(vec2 a, vec2 b);
static inline f32 distsq3(vec3 a, vec3 b);
static inline f32 distsq4(vec4 a, vec4 b);

static inline f32 dist2(vec2 a, vec2 b);
static inline f32 dist3(vec3 a, vec3 b);
static inline f32 dist4(vec4 a, vec4 b);

// Angle between vectors
static inline f32 angle2(vec2 a, vec2 b);
static inline f32 angle3(vec3 a, vec3 b);
static inline f32 angle2_fast(vec2 a, vec2 b); // assumes normalized, may NaN
static inline f32 angle3_fast(vec3 a, vec3 b); // assumes normalized, may NaN

// Scalar projection of a onto b (length of projection).
// Returns: (a · b) / |b|
static inline f32 scalarproj2(vec2 a, vec2 b);
static inline f32 scalarproj3(vec3 a, vec3 b);

// Multiplication by b gets the projection.
// Returns: (a · b) / |b|^2
static inline f32 projcoeff2(vec2 a, vec2 b);
static inline f32 projcoeff3(vec3 a, vec3 b);

// Vector projection of a onto b.
// Returns: b * projcoef(a, b)
static inline vec2 proj2(vec2 a, vec2 b);
static inline vec3 proj3(vec3 a, vec3 b);

// Rejection: component of a perpendicular to b.
// Returns: a - proj(a onto b)
static inline vec2 rej2(vec2 a, vec2 b);
static inline vec3 rej3(vec3 a, vec3 b);

// Reflection of a about normalized b (b must be unit length).
// Returns: a - 2 * (a · b) * b
static inline vec2 refl2(vec2 a, vec2 b);
static inline vec3 refl3(vec3 a, vec3 b);

// Linear interpolation
static inline f32 lerp(f32 a, f32 b, f32 t);
static inline vec2 lerp2(vec2 a, vec2 b, f32 t);
static inline vec3 lerp3(vec3 a, vec3 b, f32 t);
static inline vec4 lerp4(vec4 a, vec4 b, f32 t);

// Min/Max
static inline f32 min(f32 a, f32 b);
static inline vec2 min2(vec2 a, vec2 b);
static inline vec3 min3(vec3 a, vec3 b);
static inline vec4 min4(vec4 a, vec4 b);

static inline f32 max(f32 a, f32 b);
static inline vec2 max2(vec2 a, vec2 b);
static inline vec3 max3(vec3 a, vec3 b);
static inline vec4 max4(vec4 a, vec4 b);

// Clamping
static inline f32 clamp(f32 value, f32 min_value, f32 max_value);
static inline vec2 clamp2(vec2 value, vec2 min_value, vec2 max_value);
static inline vec3 clamp3(vec3 value, vec3 min_value, vec3 max_value);
static inline vec4 clamp4(vec4 value, vec4 min_value, vec4 max_value);

// Matrix constructors
static inline mat2 M2(vec2 c0, vec2 c1);
static inline mat3 M3(vec3 c0, vec3 c1, vec3 c2);
static inline mat4 M4(vec4 c0, vec4 c1, vec4 c2, vec4 c3);

// Identity matrix constructors
static inline mat2 I2(void);
static inline mat3 I3(void);
static inline mat4 I4(void);

// Zero matrix constructors
static inline mat2 Z2(void);
static inline mat3 Z3(void);
static inline mat4 Z4(void);

static inline mat2 transpose2(mat2 m);
static inline mat3 transpose3(mat3 m);
static inline mat4 transpose4(mat4 m);


static inline f32 clamp01(f32 value);
static inline f32 ilerp(f32 a, f32 b, f32 v);
static inline f32 smoothstep(f32 e0, f32 e1, f32 x);
static inline f32 smootherstep(f32 e0, f32 e1, f32 x);
static inline f32 step(f32 edge, f32 x);
static inline f32 inverse_smoothstep(f32 x);
static inline f32 repeat(f32 x, f32 max); // max must be > 0
static inline f32 pingpong(f32 x, f32 l); // creates a triangle wave that goes 0 → l → 0 → l … with period 2l
static inline f32 sign(f32 x); // returns 0 for 0
static inline f32 deg2rad(f32 d);
static inline f32 rad2deg(f32 r);


// Vector functions
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

static inline vec2 v2s(f32 s) { return v2(s, s); }
static inline vec3 v3s(f32 s) { return v3(s, s, s); }
static inline vec4 v4s(f32 s) { return v4(s, s, s, s); }

static inline vec3 v3v2(vec2 xy, f32 z) { return v3(xy.x, xy.y, z); }
static inline vec4 v4v3(vec3 xyz, f32 w) { return v4(xyz.x, xyz.y, xyz.z, w); }
static inline vec4 v4v2(vec2 xy, f32 z, f32 w) { return v4(xy.x, xy.y, z, w); }

static inline vec2 v2v3(vec3 v) { return v2(v.x, v.y); }
static inline vec2 v2v4(vec4 v) { return v2(v.x, v.y); }
static inline vec3 v3v4(vec4 v) { return v3(v.x, v.y, v.z); }

static inline vec2 add2(vec2 a, vec2 b) { return v2(a.x + b.x, a.y + b.y); }
static inline vec3 add3(vec3 a, vec3 b) { return v3(a.x + b.x, a.y + b.y, a.z + b.z); }
static inline vec4 add4(vec4 a, vec4 b) { return v4(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w); }

static inline vec2 sub2(vec2 a, vec2 b) { return v2(a.x - b.x, a.y - b.y); }
static inline vec3 sub3(vec3 a, vec3 b) { return v3(a.x - b.x, a.y - b.y, a.z - b.z); }
static inline vec4 sub4(vec4 a, vec4 b) { return v4(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w); }

static inline vec2 mul2(vec2 a, vec2 b) { return v2(a.x * b.x, a.y * b.y); }
static inline vec3 mul3(vec3 a, vec3 b) { return v3(a.x * b.x, a.y * b.y, a.z * b.z); }
static inline vec4 mul4(vec4 a, vec4 b) { return v4(a.x * b.x, a.y * b.y, a.z * b.z, a.w * b.w); }

static inline vec2 div2(vec2 a, vec2 b) { return v2(a.x / b.x, a.y / b.y); }
static inline vec3 div3(vec3 a, vec3 b) { return v3(a.x / b.x, a.y / b.y, a.z / b.z); }
static inline vec4 div4(vec4 a, vec4 b) { return v4(a.x / b.x, a.y / b.y, a.z / b.z, a.w / b.w); }

static inline vec2 add2s(vec2 a, f32 s) { return v2(a.x + s, a.y + s); }
static inline vec3 add3s(vec3 a, f32 s) { return v3(a.x + s, a.y + s, a.z + s); }
static inline vec4 add4s(vec4 a, f32 s) { return v4(a.x + s, a.y + s, a.z + s, a.w + s); }

static inline vec2 sub2s(vec2 a, f32 s) { return v2(a.x - s, a.y - s); }
static inline vec3 sub3s(vec3 a, f32 s) { return v3(a.x - s, a.y - s, a.z - s); }
static inline vec4 sub4s(vec4 a, f32 s) { return v4(a.x - s, a.y - s, a.z - s, a.w - s); }

static inline vec2 mul2s(vec2 a, f32 s) { return v2(a.x * s, a.y * s); }
static inline vec3 mul3s(vec3 a, f32 s) { return v3(a.x * s, a.y * s, a.z * s); }
static inline vec4 mul4s(vec4 a, f32 s) { return v4(a.x * s, a.y * s, a.z * s, a.w * s); }

static inline vec2 div2s(vec2 a, f32 s) { return v2(a.x / s, a.y / s); }
static inline vec3 div3s(vec3 a, f32 s) { return v3(a.x / s, a.y / s, a.z / s); }
static inline vec4 div4s(vec4 a, f32 s) { return v4(a.x / s, a.y / s, a.z / s, a.w / s); }

static inline f32 dot2(vec2 a, vec2 b) { return a.x * b.x + a.y * b.y; }
static inline f32 dot3(vec3 a, vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline f32 dot4(vec4 a, vec4 b) { return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w; }

static inline vec3 cross(vec3 a, vec3 b)
{
    return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

static inline f32 lensq2(vec2 a) { return dot2(a, a); }
static inline f32 lensq3(vec3 a) { return dot3(a, a); }
static inline f32 lensq4(vec4 a) { return dot4(a, a); }

static inline f32 len2(vec2 a) { return sqrtf(lensq2(a)); }
static inline f32 len3(vec3 a) { return sqrtf(lensq3(a)); }
static inline f32 len4(vec4 a) { return sqrtf(lensq4(a)); }

static inline vec2 norm2(vec2 a) { return mul2s(a, 1.0f / len2(a)); }
static inline vec3 norm3(vec3 a) { return mul3s(a, 1.0f / len3(a)); }
static inline vec4 norm4(vec4 a) { return mul4s(a, 1.0f / len4(a)); }

static inline f32 distsq2(vec2 a, vec2 b) { return lensq2(sub2(a, b)); }
static inline f32 distsq3(vec3 a, vec3 b) { return lensq3(sub3(a, b)); }
static inline f32 distsq4(vec4 a, vec4 b) { return lensq4(sub4(a, b)); }

static inline f32 dist2(vec2 a, vec2 b) { return sqrtf(distsq2(a, b)); }
static inline f32 dist3(vec3 a, vec3 b) { return sqrtf(distsq3(a, b)); }
static inline f32 dist4(vec4 a, vec4 b) { return sqrtf(distsq4(a, b)); }

static inline f32 angle2(vec2 a, vec2 b)
{
    f32 denom = len2(a) * len2(b);
    if (denom == 0.0f) return 0.0f;

    f32 cosine = dot2(a, b) / denom;
    cosine = clamp(cosine, -1.0f, 1.0f);
    return acosf(cosine);
}
static inline f32 angle3(vec3 a, vec3 b)
{
    f32 denom = len3(a) * len3(b);
    if (denom == 0.0f) return 0.0f;

    f32 cosine = dot3(a, b) / denom;
    cosine = clamp(cosine, -1.0f, 1.0f);
    return acosf(cosine);
}
static inline f32 angle2_fast(vec2 a, vec2 b) { return acosf(dot2(a, b)); }
static inline f32 angle3_fast(vec3 a, vec3 b) { return acosf(dot3(a, b)); }

static inline f32 scalarproj2(vec2 a, vec2 b)
{
    float b_length = len2(b);
    if (b_length == 0.0f) return 0.0f;
    return dot2(a, b) / b_length;
}
static inline f32 scalarproj3(vec3 a, vec3 b)
{
    float b_length = len3(b);
    if (b_length == 0.0f) return 0.0f;
    return dot3(a, b) / b_length;
}

static inline float projcoeff2(vec2 a, vec2 b)
{
    f32 denom = dot2(b, b);
    if (denom == 0.0f) return 0.0f;
    return dot2(a, b) / denom;
}
static inline float projcoeff3(vec3 a, vec3 b)
{
    f32 denom = dot3(b, b);
    if (denom == 0.0f) return 0.0f;
    return dot3(a, b) / denom;
}

static inline vec2 proj2(vec2 a, vec2 b) { return mul2s(b, projcoeff2(a, b)); }
static inline vec3 proj3(vec3 a, vec3 b) { return mul3s(b, projcoeff3(a, b)); }

static inline vec2 rej2(vec2 a, vec2 b) { return sub2(a, proj2(a, b)); }
static inline vec3 rej3(vec3 a, vec3 b) { return sub3(a, proj3(a, b)); }

static inline vec2 refl2(vec2 a, vec2 b) { return sub2(a, mul2s(b, 2.0f * dot2(a, b))); }
static inline vec3 refl3(vec3 a, vec3 b) { return sub3(a, mul3s(b, 2.0f * dot3(a, b))); }

static inline f32 lerp(f32 a, f32 b, f32 t)
{
    return a + (b - a) * t;
}
static inline vec2 lerp2(vec2 a, vec2 b, f32 t)
{
    return v2(lerp(a.x, b.x, t), lerp(a.y, b.y, t));
}
static inline vec3 lerp3(vec3 a, vec3 b, f32 t)
{
    return v3(lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t));
}
static inline vec4 lerp4(vec4 a, vec4 b, f32 t)
{
    return v4(lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t), lerp(a.w, b.w, t));
}

static inline f32 min(f32 a, f32 b)
{
    return a < b ? a : b;
}
static inline vec2 min2(vec2 a, vec2 b)
{
    return v2(min(a.x, b.x), min(a.y, b.y));
}
static inline vec3 min3(vec3 a, vec3 b)
{
    return v3(min(a.x, b.x),
              min(a.y, b.y),
              min(a.z, b.z));
}
static inline vec4 min4(vec4 a, vec4 b)
{
    return v4(min(a.x, b.x),
              min(a.y, b.y),
              min(a.z, b.z),
              min(a.w, b.w));
}

static inline f32 max(f32 a, f32 b)
{
    return a > b ? a : b;
}
static inline vec2 max2(vec2 a, vec2 b)
{
    return v2(max(a.x, b.x), max(a.y, b.y));
}
static inline vec3 max3(vec3 a, vec3 b)
{
    return v3(max(a.x, b.x),
              max(a.y, b.y),
              max(a.z, b.z));
}
static inline vec4 max4(vec4 a, vec4 b)
{
    return v4(max(a.x, b.x),
              max(a.y, b.y),
              max(a.z, b.z),
              max(a.w, b.w));
}

static inline f32 clamp(f32 value, f32 min_value, f32 max_value)
{
    return max(min_value, min(value, max_value));
}
static inline vec2 clamp2(vec2 value, vec2 min_value, vec2 max_value)
{
    return max2(min_value, min2(value, max_value));
}
static inline vec3 clamp3(vec3 value, vec3 min_value, vec3 max_value)
{
    return max3(min_value, min3(value, max_value));
}
static inline vec4 clamp4(vec4 value, vec4 min_value, vec4 max_value)
{
    return max4(min_value, min4(value, max_value));
}

// Matrix functions

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

static inline mat2 Z2(void)
{
    mat2 result = {0};
    return result;
}

static inline mat3 Z3(void)
{
    mat3 result = {0};
    return result;
}

static inline mat4 Z4(void)
{
    mat4 result = {0};
    return result;
}

static inline mat2 transpose2(mat2 m)
{
    mat2 r = {
        m.m00, m.m10,
        m.m01, m.m11
    };
    return r;
}

static inline mat3 transpose3(mat3 m)
{
    mat3 r = {
        m.m00, m.m10, m.m20,
        m.m01, m.m11, m.m21,
        m.m02, m.m12, m.m22
    };
    return r;
}

static inline mat4 transpose4(mat4 m)
{
    mat4 r = {
        m.m00, m.m10, m.m20, m.m30,
        m.m01, m.m11, m.m21, m.m31,
        m.m02, m.m12, m.m22, m.m32,
        m.m03, m.m13, m.m23, m.m33
    };
    return r;
}

// Utility functions

static inline f32 clamp01(f32 value)
{
    return clamp(value, 0.0f, 1.0f);
}

static inline f32 ilerp(f32 a, f32 b, f32 v)
{
    return (v - a) / (b - a);
}

static inline f32 smoothstep(f32 e0, f32 e1, f32 x)
{
    f32 t = clamp01(ilerp(e0, e1, x));;
    return t * t * (3.0f - 2.0f * t);
}

static inline f32 smootherstep(f32 e0, f32 e1, f32 x)
{
    f32 t = clamp01(ilerp(e0, e1, x));
    return t * t * t * (t * (6.0f * t - 15.0f) + 10.0f);
}

static inline f32 step(f32 edge, f32 x)
{
    return x < edge ? 0.0f : 1.0f;
}

static inline f32 inverse_smoothstep(f32 x)
{
    return 0.5f - sinf(asinf(1.0f - 2.0f * x) / 3.0f);
}

static inline f32 repeat(f32 x, f32 max)
{
    return x - floorf(x / max) * max;
}

static inline f32 pingpong(f32 x, f32 l)
{
    f32 t = repeat(x, 2.0f * l);
    return l - fabsf(t - l);
}

static inline f32 sign(f32 x)
{
    return (x > 0.0f) - (x < 0.0f);
}

static inline f32 deg2rad(f32 d)
{
    return d * (PI / 180.0f);
}

static inline f32 rad2deg(f32 r)
{
    return r * (180.0f / PI);
}

#endif // _XTBM_H_
