#version 330 core

// Per vertex data
layout (location = 0) in float t;
layout (location = 1) in float side;

// Instanced data
layout (location = 2) in vec2 aPrev;
layout (location = 3) in vec2 aCurrentStart;
layout (location = 4) in vec2 aCurrentEnd;
layout (location = 5) in vec2 aNext;

uniform mat4 uProjection;
uniform float uThickness;

struct MiterData
{
    vec2 miter;
    float length;
};

MiterData compute_miter(vec2 prev, vec2 current, vec2 next)
{
    vec2 dir_a = normalize(current - prev);
    vec2 dir_b = normalize(next - current);

    if (length(next - current) < 1e-5)
        dir_b = dir_a;
    if (length(current - prev) < 1e-5)
        dir_a = dir_b;

    vec2 normal_a = vec2(-dir_a.y, dir_a.x);
    vec2 normal_b = vec2(-dir_b.y, dir_b.x);
    vec2 tangent = normalize(dir_a + dir_b);

    vec2 miter = vec2(-tangent.y, tangent.x);
    float miter_len = 1.0f / dot(miter, normal_a);

    MiterData mdata;
    mdata.miter = miter;
    mdata.length = miter_len;
    return mdata;
}

void main()
{
    float halfWidth = uThickness * 0.5;
    vec2 dir = aCurrentEnd - aCurrentStart;
    vec2 normal = normalize(vec2(-dir.y, dir.x));

    vec2 miterOffset;
    if (t < 0.5)
    {
        MiterData miterA = compute_miter(aPrev, aCurrentStart, aCurrentEnd);
        miterOffset = miterA.miter * (miterA.length * halfWidth);
    }
    else
    {
        MiterData miterB = compute_miter(aCurrentStart, aCurrentEnd, aNext);
        miterOffset = miterB.miter * (miterB.length * halfWidth);
    }

    vec2 selectedSegmentEnd = (1.0 - t) * aCurrentStart + t * aCurrentEnd;
    vec2 position = selectedSegmentEnd + (side * miterOffset);

    gl_Position = uProjection * vec4(position, 0.0, 1.0);
}
