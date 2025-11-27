#ifndef _XTBM_H_
#define _XTBM_H_

#include <math.h>
#include <stdbool.h>

#define PI 3.14159265359f
// #define E 2.71828f
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
    struct { vec2 col0, col1; };
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
    struct { vec3 col0, col1, col2; };
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
    struct { vec4 col0, col1, col2, col3; };
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

static inline vec2 neg2(vec2 a);
static inline vec3 neg3(vec3 a);
static inline vec4 neg4(vec4 a);

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

static inline vec3 v3_euler(f32 yaw, f32 pitch);

// Matrix constructors
static inline mat2 M2(vec2 c0, vec2 c1);
static inline mat3 M3(vec3 c0, vec3 c1, vec3 c2);
static inline mat4 M4(vec4 c0, vec4 c1, vec4 c2, vec4 c3);

// Truncating constructors
static inline mat2 M2M3(mat3 m);
static inline mat2 M2M4(mat4 m);
static inline mat3 M3M4(mat4 m);

// Identity matrix constructors
static inline mat2 I2(void);
static inline mat3 I3(void);
static inline mat4 I4(void);

// Zero matrix constructors
static inline mat2 Z2(void);
static inline mat3 Z3(void);
static inline mat4 Z4(void);

static inline mat2 mmul2s(mat2 m, f32 s);
static inline mat3 mmul3s(mat3 m, f32 s);
static inline mat4 mmul4s(mat4 m, f32 s);

// Matrix-vector multiplication
static inline vec2 mvmul2(mat2 m, vec2 v);
static inline vec3 mvmul3(mat3 m, vec3 v);
static inline vec4 mvmul4(mat4 m, vec4 v);

// Matrix-matrix multiplication
static inline mat2 mmul2(mat2 a, mat2 b);
static inline mat3 mmul3(mat3 a, mat3 b);
static inline mat4 mmul4(mat4 a, mat4 b);

// Matrix transposition
static inline mat2 transpose2(mat2 m);
static inline mat3 transpose3(mat3 m);
static inline mat4 transpose4(mat4 m);

static inline f32 det2(mat2 m);
static inline f32 det3(mat3 m);
static inline f32 det4(mat4 m);

static inline mat3 inverse3(mat3 m);
static inline mat4 affine_inverse4(mat4 m);
static inline bool is_affine4(mat4 m);

// Linear/Affine transformations
static inline mat4 make_translate4(vec3 offset);
static inline mat4 make_scale4(vec3 scalars);
static inline mat4 make_uniform_scale4(f32 scalar);
static inline mat4 make_rotate4_x(f32 angle);
static inline mat4 make_rotate4_z(f32 angle);
static inline mat4 make_rotate4_y(f32 angle);
static inline mat4 make_rotate4_axis(vec3 axis, f32 angle);
static inline mat4 make_rotate4_euler(f32 yaw, f32 pitch, f32 roll);

static inline mat4 translate4(mat4 base, vec3 offset);
static inline mat4 scale4(mat4 base, vec3 scalars);
static inline mat4 uniform_scale4(mat4 base, f32 scalar);
static inline mat4 rotate4_x(mat4 base, f32 angle);
static inline mat4 rotate4_y(mat4 base, f32 angle);
static inline mat4 rotate4_z(mat4 base, f32 angle);
static inline mat4 rotate4_axis(mat4 base, vec3 axis, f32 angle);
static inline mat4 rotate4_euler(mat4 base, f32 yaw, f32 pitch, f32 roll);

// Projections
static inline mat4 ortho(f32 l, f32 r, f32 b, f32 t, f32 n, f32 f);
static inline mat4 ortho2d(f32 l, f32 r, f32 b, f32 t);
static inline mat4 ortho2d_screen(f32 width, f32 height);
static inline mat4 perspective(f32 fovy, f32 aspect, f32 near, f32 far);

static inline mat4 look_at(vec3 position, vec3 direction, vec3 up);

static inline f32 fract(f32 f);
static inline f32 clamp01(f32 value);
static inline f32 unlerp(f32 a, f32 b, f32 v);
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

static inline vec2 neg2(vec2 a) { return mul2s(a, -1.0f); }
static inline vec3 neg3(vec3 a) { return mul3s(a, -1.0f); }
static inline vec4 neg4(vec4 a) { return mul4s(a, -1.0f); }

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
    f32 b_length = len2(b);
    if (b_length == 0.0f) return 0.0f;
    return dot2(a, b) / b_length;
}
static inline f32 scalarproj3(vec3 a, vec3 b)
{
    f32 b_length = len3(b);
    if (b_length == 0.0f) return 0.0f;
    return dot3(a, b) / b_length;
}

static inline f32 projcoeff2(vec2 a, vec2 b)
{
    f32 denom = dot2(b, b);
    if (denom == 0.0f) return 0.0f;
    return dot2(a, b) / denom;
}
static inline f32 projcoeff3(vec3 a, vec3 b)
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

static inline vec3 v3_euler(f32 yaw, f32 pitch)
{
    f32 y = deg2rad(yaw);
    f32 p = deg2rad(pitch);
    return v3(
        sinf(y) * cosf(p),
        sinf(p),
        -cosf(y) * cosf(p)
    );
}

// Matrix functions

static inline mat2 M2(vec2 c0, vec2 c1)
{
    mat2 m;
    m.col0 = c0;
    m.col1 = c1;
    return m;
}
static inline mat3 M3(vec3 c0, vec3 c1, vec3 c2)
{
    mat3 m;
    m.col0 = c0;
    m.col1 = c1;
    m.col2 = c2;
    return m;
}
static inline mat4 M4(vec4 c0, vec4 c1, vec4 c2, vec4 c3)
{
    mat4 m;
    m.col0 = c0;
    m.col1 = c1;
    m.col2 = c2;
    m.col3 = c3;
    return m;
}

static inline mat2 M2M3(mat3 m)
{
    return M2(
        v2v3(m.col0),
        v2v3(m.col1)
    );
}

static inline mat2 M2M4(mat4 m)
{
    return M2(
        v2v4(m.col0),
        v2v4(m.col1)
    );
}

static inline mat3 M3M4(mat4 m)
{
    return M3(
        v3v4(m.col0),
        v3v4(m.col1),
        v3v4(m.col2)
    );
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

static inline mat2 mmul2s(mat2 m, f32 s)
{
    m.col0 = mul2s(m.col0, s);
    m.col1 = mul2s(m.col1, s);
    return m;
}

static inline mat3 mmul3s(mat3 m, f32 s)
{
    m.col0 = mul3s(m.col0, s);
    m.col1 = mul3s(m.col1, s);
    m.col2 = mul3s(m.col2, s);
    return m;
}

static inline mat4 mmul4s(mat4 m, f32 s)
{
    m.col0 = mul4s(m.col0, s);
    m.col1 = mul4s(m.col1, s);
    m.col2 = mul4s(m.col2, s);
    m.col3 = mul4s(m.col3, s);
    return m;
}

static inline vec2 mvmul2(mat2 m, vec2 v)
{
    return add2(
            mul2s(m.col0, v.x),
            mul2s(m.col1, v.y));
}
static inline vec3 mvmul3(mat3 m, vec3 v)
{
    return add3(
            add3(mul3s(m.col0, v.x),
                 mul3s(m.col1, v.y)),
            mul3s(m.col2, v.z));
}
static inline vec4 mvmul4(mat4 m, vec4 v)
{
    return add4(
            add4(mul4s(m.col0, v.x),
                 mul4s(m.col1, v.y)),
            add4(mul4s(m.col2, v.z),
                 mul4s(m.col3, v.w)));
}

static inline mat2 mmul2(mat2 a, mat2 b)
{
    return M2(mvmul2(a, b.col0),
              mvmul2(a, b.col1));
}
static inline mat3 mmul3(mat3 a, mat3 b)
{
    return M3(mvmul3(a, b.col0),
              mvmul3(a, b.col1),
              mvmul3(a, b.col2));
}
static inline mat4 mmul4(mat4 a, mat4 b)
{
    return M4(mvmul4(a, b.col0),
              mvmul4(a, b.col1),
              mvmul4(a, b.col2),
              mvmul4(a, b.col3));
}

static inline mat2 transpose2(mat2 m)
{
    return M2(
        v2(m.m00, m.m10),
        v2(m.m01, m.m11)
    );
}

static inline mat3 transpose3(mat3 m)
{
    return M3(
        v3(m.m00, m.m10, m.m20),
        v3(m.m01, m.m11, m.m21),
        v3(m.m02, m.m12, m.m22)
    );
}

static inline mat4 transpose4(mat4 m)
{
    return M4(
        v4(m.m00, m.m10, m.m20, m.m30),
        v4(m.m01, m.m11, m.m21, m.m31),
        v4(m.m02, m.m12, m.m22, m.m32),
        v4(m.m03, m.m13, m.m23, m.m33)
    );
}

static inline f32 det2(mat2 m)
{
    return m.m00 * m.m11 - m.m10 * m.m01;
}
static inline f32 det3(mat3 m)
{
    return m.m00 * m.m11 * m.m22
         + m.m10 * m.m21 * m.m02
         + m.m20 * m.m01 * m.m12
         - m.m00 * m.m21 * m.m12
         - m.m10 * m.m01 * m.m22
         - m.m20 * m.m11 * m.m02;
}
static inline f32 det4(mat4 m)
{
    return m.m00 * m.m11 * m.m22 * m.m33
         + m.m10 * m.m21 * m.m32 * m.m03
         + m.m20 * m.m32 * m.m02 * m.m13
         + m.m30 * m.m01 * m.m12 * m.m23
         - m.m00 * m.m31 * m.m22 * m.m13
         - m.m10 * m.m01 * m.m32 * m.m23
         - m.m20 * m.m11 * m.m02 * m.m33
         - m.m30 * m.m21 * m.m12 * m.m03;
}

static inline mat3 inverse3(mat3 m)
{
    f32 determinant = det3(m);

    f32 a = m.m00, b = m.m10, c = m.m20;
    f32 d = m.m01, e = m.m11, f = m.m21;
    f32 g = m.m02, h = m.m12, i = m.m22;

    f32 A =  (e*i - f*h), D = -(b*i - c*h), G =  (b*f - c*e);
    f32 B = -(d*i - f*g), E =  (a*i - c*g), H = -(a*f - c*d);
    f32 C =  (d*h - e*g), F = -(a*h - b*g), I =  (a*e - b*d);

    // TODO: Determinant can be computed faster using the values above
    mat3 result = mmul3s(M3(
        v3(A, B, C),
        v3(D, E, F),
        v3(G, H, I)
    ), 1.0f / determinant);

    return result;
}

static inline mat4 affine_inverse4(mat4 m)
{
    mat3 inv3 = inverse3(M3M4(m));

    mat4 result = M4(
        v4v3(inv3.col0, 0.0f),
        v4v3(inv3.col1, 0.0f),
        v4v3(inv3.col2, 0.0f),
        v4v3(mvmul3(mmul3s(inv3, -1.0f), v3v4(m.col3)), 1.0f)
    );

    return result;
}

static inline bool is_affine4(mat4 m)
{
    return m.m03 == 0.0f && m.m13 == 0.0f && m.m23 == 0.0f && m.m33 == 1.0f;
}

static inline mat4 make_translate4(vec3 offset)
{
    mat4 result = I4();
    result.m30 = offset.x;
    result.m31 = offset.y;
    result.m32 = offset.z;
    return result;
}

static inline mat4 translate4(mat4 base, vec3 offset)
{
    return mmul4(make_translate4(offset), base);
}

static inline mat4 make_scale4(vec3 scalars)
{
    mat4 result = I4();
    result.m00 = scalars.x;
    result.m11 = scalars.y;
    result.m22 = scalars.z;
    return result;
}

static inline mat4 make_uniform_scale4(f32 scalar)
{
    return make_scale4(v3s(scalar));
}

static inline mat4 scale4(mat4 base, vec3 scalars)
{
    return mmul4(make_scale4(scalars), base);
}

static inline mat4 uniform_scale4(mat4 base, f32 scalar)
{
    return mmul4(make_uniform_scale4(scalar), base);
}

static inline mat4 make_rotate4_x(f32 angle)
{
    mat4 result = I4();
    result.m11 = cos(angle);
    result.m12 = sin(angle);
    result.m21 = -sin(angle);
    result.m22 = cos(angle);
    return result;
}

static inline mat4 make_rotate4_y(f32 angle)
{
    mat4 result = I4();
    result.m00 = cos(angle);
    result.m02 = -sin(angle);
    result.m20 = sin(angle);
    result.m22 = cos(angle);
    return result;
}

static inline mat4 make_rotate4_z(f32 angle)
{
    mat4 result = I4();
    result.m00 = cos(angle);
    result.m01 = sin(angle);
    result.m10 = -sin(angle);
    result.m11 = cos(angle);
    return result;
}

static inline mat4 make_rotate4_euler(f32 yaw, f32 pitch, f32 roll)
{
    return mmul4(
            mmul4(make_rotate4_z(yaw),
                  make_rotate4_y(pitch)),
            make_rotate4_x(roll));
}

static inline mat4 make_rotate4_axis(vec3 axis, f32 angle)
{
    // Normalize axis; if it's near zero, just return identity
    f32 len_axis = len3(axis);
    if (len_axis == 0.0f) return I4();
    axis = div3s(axis, len_axis);

    f32 ux = axis.x;
    f32 uy = axis.y;
    f32 uz = axis.z;

    f32 c = cos(angle);
    f32 s = sin(angle);
    f32 t = 1.0f - c;

    mat4 result = I4();

    result.m00 = ux*ux*t + c;
    result.m01 = ux*uy*t + uz*s;
    result.m02 = ux*uz*t - uy*s;

    result.m10 = ux*uy*t - uz*s;
    result.m11 = uy*uy*t + c;
    result.m12 = uy*uz*t + ux*s;

    result.m20 = ux*uz*t + uy*s;
    result.m21 = uy*uz*t - ux*s;
    result.m22 = uz*uz*t + c;

    return result;
}

static inline mat4 rotate4_x(mat4 base, f32 angle)
{
    return mmul4(make_rotate4_x(angle), base);
}

static inline mat4 rotate4_y(mat4 base, f32 angle)
{
    return mmul4(make_rotate4_y(angle), base);
}

static inline mat4 rotate4_z(mat4 base, f32 angle)
{
    return mmul4(make_rotate4_z(angle), base);
}

static inline mat4 rotate4_axis(mat4 base, vec3 axis, f32 angle)
{
    return mmul4(make_rotate4_axis(axis, angle), base);
}

static inline mat4 rotate4_euler(mat4 base, f32 yaw, f32 pitch, f32 roll)
{
    return mmul4(make_rotate4_euler(yaw, pitch, roll), base);
}

static inline mat4 ortho(f32 l, f32 r, f32 b, f32 t, f32 n, f32 f)
{
    vec3 scale_scalars = v3(2.0f / (r-l), 2.0f / (t-b), -2.0f / (f-n));
    vec3 translate_scalars = v3(-(r+l) / (r-l),
                                -(t+b) / (t-b),
                                -(f+n) / (f-n));

    return mmul4(make_translate4(translate_scalars), make_scale4(scale_scalars));
}

static inline mat4 ortho2d(f32 l, f32 r, f32 b, f32 t)
{
    return ortho(l, r, b, t, -1.0f, 1.0f);
}

static inline mat4 ortho2d_screen(f32 width, f32 height)
{
    return ortho2d(0.0f, width, height, 0.0f);
}

static inline mat4 perspective(f32 fovy, f32 aspect, f32 near, f32 far)
{
    f32 f = 1.0f / tan(0.5f * fovy);

    mat4 result = Z4();
    result.m00 = f / aspect;
    result.m11 = f;
    result.m22 = (far+near) / (near-far);
    result.m23 = -1;
    result.m32 = (2*far*near) / (near-far);
    return result;
}

static inline mat4 look_at(vec3 eye, vec3 center, vec3 up)
{
    vec3 f = norm3(sub3(center, eye));
    vec3 s = norm3(cross(f, up));
    vec3 u = cross(s, f);

    mat4 result = M4(
        v4( s.x,            u.x,            -f.x,           0.0f),
        v4( s.y,            u.y,            -f.y,           0.0f),
        v4( s.z,            u.z,            -f.z,           0.0f),
        v4(-dot3(s, eye),  -dot3(u, eye),   dot3(f, eye),   1.0f)
    );

    return result;
}

// Utility functions

static inline float fract(f32 f)
{
    return f - floorf(f);
}

static inline f32 clamp01(f32 value)
{
    return clamp(value, 0.0f, 1.0f);
}

static inline f32 unlerp(f32 a, f32 b, f32 v)
{
    return (v - a) / (b - a);
}

static inline f32 smoothstep(f32 e0, f32 e1, f32 x)
{
    f32 t = clamp01(unlerp(e0, e1, x));;
    return t * t * (3.0f - 2.0f * t);
}

static inline f32 smootherstep(f32 e0, f32 e1, f32 x)
{
    f32 t = clamp01(unlerp(e0, e1, x));
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
