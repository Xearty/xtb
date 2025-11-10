#version 330 core

#define POINTS_COUNT 30
#define PALETTE_SEED 34
#define POSITION_SEED 13
#define BLUR 0.3
#define FRAME_PADDING 0.01
#define SPEED 0.2

uniform float iTime;
uniform vec2 iResolution;

in vec2 texCoords;
in vec3 position;
in vec3 localPosition;
in vec3 normal;

out vec4 fragColor;

struct TriplanarUV
{
    vec2 x;
    vec2 y;
    vec2 z;
};

TriplanarUV GetTriplanarUV(vec3 pos)
{
    pos = fract(abs(pos));

    TriplanarUV triUV;
    triUV.x = pos.zy;
    triUV.y = pos.xz;
    triUV.z = pos.xy;
    return triUV;
}

vec3 GetTriplanarWeights(vec3 normal)
{
    vec3 blendWeights = abs(normal) - 0.2;
    blendWeights *= 7.0;
    blendWeights = pow(blendWeights, vec3(3.0));
    blendWeights = max(blendWeights, 0.0);
    blendWeights /= dot(blendWeights, vec3(1.0));
    return blendWeights;
}

float Random(float x)
{
    return fract(sin(x * 12.9898) * 43758.5453);
}

float LinearNoise1d(float x)
{
    return mix(Random(floor(x)), Random(floor(x) + 1.), fract(x));
}

float Remap(float i1, float i2, float o1, float o2, float x)
{
    return o1 + (x - i1) / (i2 - i1) * (o2 - o1);
}

struct PointInfo
{
    float dist;
    vec3 col;
};

vec3 GetVoronoiColor(vec2 uv, float aspectRatio)
{
    PointInfo info[POINTS_COUNT];
    float minDist = 10000.;

    for (int i = 0; i < POINTS_COUNT; i++)
    {
        float x = Random(float(i) + float(POSITION_SEED) * 534.) * aspectRatio;
        float y = Random(float(i) + float(POSITION_SEED) * 123.);

        float t = iTime * SPEED;
        t *= Remap(0., 1., .9, 1., Random(float(i) * 12.5125));
        float dx = Remap(0., 1., -x + FRAME_PADDING, -x + aspectRatio - FRAME_PADDING, LinearNoise1d(float(i) * 43. + t));
        float dy = Remap(0., 1., -y + FRAME_PADDING, -y + 1. - FRAME_PADDING, LinearNoise1d(float(i) * 261. + t));

        x += dx;
        y += dy;

        float dist = length(uv - vec2(x, y));

        float r = Random(float(i) * float(PALETTE_SEED) + 0.);
        float g = Random(float(i) * float(PALETTE_SEED) + 100.);
        float b = Random(float(i) * float(PALETTE_SEED) + 200.);

        info[i].dist = dist;
        info[i].col = vec3(r, g, b);

        if (minDist > dist)
        {
            minDist = dist;
        }
    }

    vec3 col = vec3(0.);

    for (int i = 0; i < POINTS_COUNT; i++)
    {
        float c = smoothstep(minDist + BLUR, minDist, info[i].dist);
        col = mix(col, info[i].col, c);
    }

    return col;
}

void main()
{
    vec2 uv = texCoords;;
    float aspectRatio = iResolution.x / iResolution.y;
    uv.x *= aspectRatio;

    TriplanarUV triUV = GetTriplanarUV(localPosition * 2.0);
    vec3 weights = GetTriplanarWeights(normal);

    vec3 albedoX = GetVoronoiColor(triUV.x, aspectRatio);
    vec3 albedoY = GetVoronoiColor(triUV.y, aspectRatio);
    vec3 albedoZ = GetVoronoiColor(triUV.z, aspectRatio);

    vec3 col = weights.x * albedoX + weights.y * albedoY + weights.z * albedoZ;

    fragColor = vec4(col, 1.0);
}
