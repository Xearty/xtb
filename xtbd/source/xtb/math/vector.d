module xtb.math.vector;

@safe nothrow @nogc:

import core.stdc.math : acosf, cosf, sinf, sqrtf;
import xtb.math.scalar : clamp, degrees, lerp, max, min, radians;

struct Vector2
{
    pure nothrow @safe @nogc:

    float x;
    float y;

    pure Vector2 opUnary(string op : "-")() const { return Vector2(-x, -y); }
    pure Vector2 opBinary(string op : "+")(Vector2 b) const { return Vector2(x + b.x, y + b.y); }
    pure Vector2 opBinary(string op : "-")(Vector2 b) const { return Vector2(x - b.x, y - b.y); }
    pure Vector2 opBinary(string op : "*")(Vector2 b) const { return Vector2(x * b.x, y * b.y); }
    pure Vector2 opBinary(string op : "/")(Vector2 b) const { return Vector2(x / b.x, y / b.y); }
    pure Vector2 opBinary(string op : "*")(float s) const { return Vector2(x * s, y * s); }
    pure Vector2 opBinary(string op : "/")(float s) const { return Vector2(x / s, y / s); }
    pure Vector2 opBinary(string op : "+")(float s) const { return Vector2(x + s, y + s); }
    pure Vector2 opBinary(string op : "-")(float s) const { return Vector2(x - s, y - s); }
    pure Vector2 opBinaryRight(string op : "*")(float s) const { return this * s; }
}

struct Vector3
{
    pure nothrow @safe @nogc:

    float x;
    float y;
    float z;

    pure Vector3 opUnary(string op : "-")() const { return Vector3(-x, -y, -z); }
    pure Vector3 opBinary(string op : "+")(Vector3 b) const
    { return Vector3(x + b.x, y + b.y, z + b.z); }
    pure Vector3 opBinary(string op : "-")(Vector3 b) const
    { return Vector3(x - b.x, y - b.y, z - b.z); }
    pure Vector3 opBinary(string op : "*")(Vector3 b) const
    { return Vector3(x * b.x, y * b.y, z * b.z); }
    pure Vector3 opBinary(string op : "/")(Vector3 b) const
    { return Vector3(x / b.x, y / b.y, z / b.z); }
    pure Vector3 opBinary(string op : "*")(float s) const { return Vector3(x * s, y * s, z * s); }
    pure Vector3 opBinary(string op : "/")(float s) const { return Vector3(x / s, y / s, z / s); }
    pure Vector3 opBinary(string op : "+")(float s) const { return Vector3(x + s, y + s, z + s); }
    pure Vector3 opBinary(string op : "-")(float s) const { return Vector3(x - s, y - s, z - s); }
    pure Vector3 opBinaryRight(string op : "*")(float s) const { return this * s; }
}

struct Vector4
{
    pure nothrow @safe @nogc:

    float x;
    float y;
    float z;
    float w;

    pure Vector4 opUnary(string op : "-")() const { return Vector4(-x, -y, -z, -w); }
    pure Vector4 opBinary(string op : "+")(Vector4 b) const
    { return Vector4(x + b.x, y + b.y, z + b.z, w + b.w); }
    pure Vector4 opBinary(string op : "-")(Vector4 b) const
    { return Vector4(x - b.x, y - b.y, z - b.z, w - b.w); }
    pure Vector4 opBinary(string op : "*")(Vector4 b) const
    { return Vector4(x * b.x, y * b.y, z * b.z, w * b.w); }
    pure Vector4 opBinary(string op : "/")(Vector4 b) const
    { return Vector4(x / b.x, y / b.y, z / b.z, w / b.w); }
    pure Vector4 opBinary(string op : "*")(float s) const
    { return Vector4(x * s, y * s, z * s, w * s); }
    pure Vector4 opBinary(string op : "/")(float s) const
    { return Vector4(x / s, y / s, z / s, w / s); }
    pure Vector4 opBinary(string op : "+")(float s) const
    { return Vector4(x + s, y + s, z + s, w + s); }
    pure Vector4 opBinary(string op : "-")(float s) const
    { return Vector4(x - s, y - s, z - s, w - s); }
    pure Vector4 opBinaryRight(string op : "*")(float s) const { return this * s; }
}

pure Vector2 xy(Vector3 v) { return Vector2(v.x, v.y); }
pure Vector2 xy(Vector4 v) { return Vector2(v.x, v.y); }
pure Vector3 xyz(Vector4 v) { return Vector3(v.x, v.y, v.z); }
pure Vector3 withZ(Vector2 v, float z) { return Vector3(v.x, v.y, z); }
pure Vector4 withW(Vector3 v, float w) { return Vector4(v.x, v.y, v.z, w); }

pure float dot(Vector2 a, Vector2 b) { return a.x * b.x + a.y * b.y; }
pure float dot(Vector3 a, Vector3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
pure float dot(Vector4 a, Vector4 b) { return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w; }
pure Vector3 cross(Vector3 a, Vector3 b)
{ return Vector3(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x); }

pure float lengthSquared(Vector2 v) { return dot(v, v); }
pure float lengthSquared(Vector3 v) { return dot(v, v); }
pure float lengthSquared(Vector4 v) { return dot(v, v); }
float length(Vector2 v) { return sqrtf(v.lengthSquared); }
float length(Vector3 v) { return sqrtf(v.lengthSquared); }
float length(Vector4 v) { return sqrtf(v.lengthSquared); }
Vector2 normalized(Vector2 v) { const n=v.length; return n == 0 ? Vector2.init : v/n; }
Vector3 normalized(Vector3 v) { const n=v.length; return n == 0 ? Vector3.init : v/n; }
Vector4 normalized(Vector4 v) { const n=v.length; return n == 0 ? Vector4.init : v/n; }

pure float distanceSquared(Vector2 a, Vector2 b) { return (a-b).lengthSquared; }
pure float distanceSquared(Vector3 a, Vector3 b) { return (a-b).lengthSquared; }
pure float distanceSquared(Vector4 a, Vector4 b) { return (a-b).lengthSquared; }
float distance(Vector2 a, Vector2 b) { return (a-b).length; }
float distance(Vector3 a, Vector3 b) { return (a-b).length; }
float distance(Vector4 a, Vector4 b) { return (a-b).length; }

float angle(Vector2 a, Vector2 b)
{ const d=a.length*b.length; return d == 0 ? 0 : acosf(clamp(dot(a,b)/d,-1,1)); }
float angle(Vector3 a, Vector3 b)
{ const d=a.length*b.length; return d == 0 ? 0 : acosf(clamp(dot(a,b)/d,-1,1)); }
float projectionLength(Vector2 a, Vector2 onto)
{ const n=onto.length; return n == 0 ? 0 : dot(a,onto)/n; }
float projectionLength(Vector3 a, Vector3 onto)
{ const n=onto.length; return n == 0 ? 0 : dot(a,onto)/n; }
pure Vector2 projectedOnto(Vector2 a, Vector2 onto)
{ const d=dot(onto,onto); return d == 0 ? Vector2.init : onto*(dot(a,onto)/d); }
pure Vector3 projectedOnto(Vector3 a, Vector3 onto)
{ const d=dot(onto,onto); return d == 0 ? Vector3.init : onto*(dot(a,onto)/d); }
pure Vector2 rejectedFrom(Vector2 a, Vector2 onto) { return a-a.projectedOnto(onto); }
pure Vector3 rejectedFrom(Vector3 a, Vector3 onto) { return a-a.projectedOnto(onto); }
pure Vector2 reflected(Vector2 v, Vector2 unitNormal) { return v-unitNormal*(2*dot(v,unitNormal)); }
pure Vector3 reflected(Vector3 v, Vector3 unitNormal) { return v-unitNormal*(2*dot(v,unitNormal)); }

pure Vector2 lerp(Vector2 a, Vector2 b, float t)
{ return Vector2(lerp(a.x,b.x,t),lerp(a.y,b.y,t)); }
pure Vector3 lerp(Vector3 a, Vector3 b, float t)
{ return Vector3(lerp(a.x,b.x,t),lerp(a.y,b.y,t),lerp(a.z,b.z,t)); }
pure Vector4 lerp(Vector4 a, Vector4 b, float t)
{ return Vector4(lerp(a.x,b.x,t),lerp(a.y,b.y,t),lerp(a.z,b.z,t),lerp(a.w,b.w,t)); }
pure Vector2 min(Vector2 a, Vector2 b) { return Vector2(min(a.x,b.x),min(a.y,b.y)); }
pure Vector3 min(Vector3 a, Vector3 b) { return Vector3(min(a.x,b.x),min(a.y,b.y),min(a.z,b.z)); }
pure Vector4 min(Vector4 a, Vector4 b)
{ return Vector4(min(a.x,b.x),min(a.y,b.y),min(a.z,b.z),min(a.w,b.w)); }
pure Vector2 max(Vector2 a, Vector2 b) { return Vector2(max(a.x,b.x),max(a.y,b.y)); }
pure Vector3 max(Vector3 a, Vector3 b) { return Vector3(max(a.x,b.x),max(a.y,b.y),max(a.z,b.z)); }
pure Vector4 max(Vector4 a, Vector4 b)
{ return Vector4(max(a.x,b.x),max(a.y,b.y),max(a.z,b.z),max(a.w,b.w)); }
pure Vector2 clamp(Vector2 v, Vector2 lo, Vector2 hi) { return max(lo,min(v,hi)); }
pure Vector3 clamp(Vector3 v, Vector3 lo, Vector3 hi) { return max(lo,min(v,hi)); }
pure Vector4 clamp(Vector4 v, Vector4 lo, Vector4 hi) { return max(lo,min(v,hi)); }


Vector3 directionFromDegrees(float yaw, float pitch)
{
    const y=radians(yaw), p=radians(pitch);
    return Vector3(sinf(y)*cosf(p), sinf(p), -cosf(y)*cosf(p));
}

static assert(Vector2.sizeof == 2 * float.sizeof);
static assert(Vector3.sizeof == 3 * float.sizeof);
static assert(Vector4.sizeof == 4 * float.sizeof);

unittest
{
    const a=Vector3(1,2,3), b=Vector3(4,5,6);
    assert(a+b == Vector3(5,7,9));
    assert(dot(a,b) == 32);
    assert(cross(Vector3(1,0,0),Vector3(0,1,0)) == Vector3(0,0,1));
    assert(Vector3.init.normalized == Vector3.init);
    assert(Vector3(3,0,0).projectedOnto(Vector3(0,2,0)) == Vector3.init);
}
