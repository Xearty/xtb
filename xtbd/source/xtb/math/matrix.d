module xtb.math.matrix;

@safe nothrow @nogc:

import core.stdc.math : cosf, sinf, tanf;
import xtb.math.vector : Vector2, Vector3, Vector4, cross, dot, normalized, withW, xyz;

struct Matrix2
{
pure nothrow @safe @nogc:

    Vector2 c0;
    Vector2 c1;

    static pure Matrix2 identity()
    {
        return Matrix2(Vector2(1, 0), Vector2(0, 1));
    }

    pure Matrix2 opBinary(string op : "*")(float s) const
    {
        return Matrix2(c0 * s, c1 * s);
    }

    pure Vector2 opBinary(string op : "*")(Vector2 v) const
    {
        return c0 * v.x + c1 * v.y;
    }

    pure Matrix2 opBinary(string op : "*")(Matrix2 b) const
    {
        return Matrix2(this * b.c0, this * b.c1);
    }
}

struct Matrix3
{
pure nothrow @safe @nogc:

    Vector3 c0;
    Vector3 c1;
    Vector3 c2;

    static pure Matrix3 identity()
    {
        return Matrix3(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1));
    }

    pure Matrix3 opBinary(string op : "*")(float s) const
    {
        return Matrix3(c0 * s, c1 * s, c2 * s);
    }

    pure Vector3 opBinary(string op : "*")(Vector3 v) const
    {
        return c0 * v.x + c1 * v.y + c2 * v.z;
    }

    pure Matrix3 opBinary(string op : "*")(Matrix3 b) const
    {
        return Matrix3(this * b.c0, this * b.c1, this * b.c2);
    }
}

struct Matrix4
{
pure nothrow @safe @nogc:

    Vector4 c0;
    Vector4 c1;
    Vector4 c2;
    Vector4 c3;

    static pure Matrix4 identity()
    {
        return Matrix4(Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0,
                1, 0), Vector4(0, 0, 0, 1));
    }

    pure Matrix4 opBinary(string op : "*")(float s) const
    {
        return Matrix4(c0 * s, c1 * s, c2 * s, c3 * s);
    }

    pure Vector4 opBinary(string op : "*")(Vector4 v) const
    {
        return c0 * v.x + c1 * v.y + c2 * v.z + c3 * v.w;
    }

    pure Matrix4 opBinary(string op : "*")(Matrix4 b) const
    {
        return Matrix4(this * b.c0, this * b.c1, this * b.c2, this * b.c3);
    }
}

static assert(Matrix2.sizeof == 4 * float.sizeof);
static assert(Matrix3.sizeof == 9 * float.sizeof);
static assert(Matrix4.sizeof == 16 * float.sizeof);

pure Matrix2 transposed(Matrix2 m)
{
    return Matrix2(Vector2(m.c0.x, m.c1.x), Vector2(m.c0.y, m.c1.y));
}

pure Matrix3 transposed(Matrix3 m)
{
    return Matrix3(Vector3(m.c0.x, m.c1.x, m.c2.x), Vector3(m.c0.y, m.c1.y,
            m.c2.y), Vector3(m.c0.z, m.c1.z, m.c2.z));
}

pure Matrix4 transposed(Matrix4 m)
{
    return Matrix4(Vector4(m.c0.x, m.c1.x, m.c2.x, m.c3.x), Vector4(m.c0.y,
            m.c1.y, m.c2.y, m.c3.y), Vector4(m.c0.z, m.c1.z, m.c2.z, m.c3.z),
        Vector4(m.c0.w, m.c1.w, m.c2.w, m.c3.w));
}

pure float determinant(Matrix2 m)
{
    return m.c0.x * m.c1.y - m.c1.x * m.c0.y;
}

pure float determinant(Matrix3 m)
{
    return dot(m.c0, cross(m.c1, m.c2));
}

pure float determinant(Matrix4 m)
{
    const a = m.c0.x, b = m.c1.x, c = m.c2.x, d = m.c3.x;
    const e = m.c0.y, f = m.c1.y, g = m.c2.y, h = m.c3.y;
    const i = m.c0.z, j = m.c1.z, k = m.c2.z, l = m.c3.z;
    const n = m.c0.w, o = m.c1.w, p = m.c2.w, q = m.c3.w;
    return a * (f * (k * q - l * p) - g * (j * q - l * o) + h * (j * p - k * o)) - b * (
        e * (k * q - l * p) - g * (i * q - l * n) + h * (i * p - k * n)) + c * (
        e * (j * q - l * o) - f * (i * q - l * n) + h * (i * o - j * n)) - d * (
        e * (j * p - k * o) - f * (i * p - k * n) + g * (i * o - j * n));
}

pure @system bool tryInverse(Matrix2 m, Matrix2* output)
{
    assert(output !is null);
    const d = m.determinant;
    if (d == 0)
        return false;
    *output = Matrix2(Vector2(m.c1.y, -m.c0.y), Vector2(-m.c1.x, m.c0.x)) * (1 / d);
    return true;
}

pure @system bool tryInverse(Matrix3 m, Matrix3* output)
{
    assert(output !is null);
    const d = m.determinant;
    if (d == 0)
        return false;
    *output = Matrix3(cross(m.c1, m.c2), cross(m.c2, m.c0), cross(m.c0, m.c1)).transposed * (1 / d);
    return true;
}

pure @system bool tryInverse(Matrix4 m, Matrix4* output)
{
    assert(output !is null);
    float[8][4] rows;
    rows[0] = [m.c0.x, m.c1.x, m.c2.x, m.c3.x, 1, 0, 0, 0];
    rows[1] = [m.c0.y, m.c1.y, m.c2.y, m.c3.y, 0, 1, 0, 0];
    rows[2] = [m.c0.z, m.c1.z, m.c2.z, m.c3.z, 0, 0, 1, 0];
    rows[3] = [m.c0.w, m.c1.w, m.c2.w, m.c3.w, 0, 0, 0, 1];
    foreach (column; 0 .. 4)
    {
        size_t pivot = column;
        float pivotMagnitude = absolute(rows[pivot][column]);
        foreach (row; column + 1 .. 4)
        {
            const magnitude = absolute(rows[row][column]);
            if (magnitude > pivotMagnitude)
            {
                pivot = row;
                pivotMagnitude = magnitude;
            }
        }
        if (pivotMagnitude == 0)
            return false;
        if (pivot != column)
        {
            const temporary = rows[column];
            rows[column] = rows[pivot];
            rows[pivot] = temporary;
        }
        const divisor = rows[column][column];
        foreach (entry; 0 .. 8)
            rows[column][entry] /= divisor;
        foreach (row; 0 .. 4)
        {
            if (row == column)
                continue;
            const factor = rows[row][column];
            foreach (entry; 0 .. 8)
                rows[row][entry] -= factor * rows[column][entry];
        }
    }
    *output = Matrix4(Vector4(rows[0][4], rows[1][4], rows[2][4], rows[3][4]),
        Vector4(rows[0][5], rows[1][5], rows[2][5], rows[3][5]),
        Vector4(rows[0][6], rows[1][6], rows[2][6], rows[3][6]),
        Vector4(rows[0][7], rows[1][7], rows[2][7], rows[3][7]));
    return true;
}

private pure float absolute(float value)
{
    return value < 0 ? -value : value;
}

pure bool isAffine(Matrix4 m)
{
    return m.c0.w == 0 && m.c1.w == 0 && m.c2.w == 0 && m.c3.w == 1;
}

pure @system bool tryAffineInverse(Matrix4 m, Matrix4* output)
{
    assert(output !is null);
    if (!m.isAffine)
        return false;
    Matrix3 linearInverse;
    if (!Matrix3(m.c0.xyz, m.c1.xyz, m.c2.xyz).tryInverse(&linearInverse))
        return false;
    const translation = -(linearInverse * m.c3.xyz);
    *output = Matrix4(linearInverse.c0.withW(0), linearInverse.c1.withW(0),
        linearInverse.c2.withW(0), translation.withW(1));
    return true;
}

pure Matrix4 translation(Vector3 offset)
{
    Matrix4 result = Matrix4.identity;
    result.c3 = offset.withW(1);
    return result;
}

pure Matrix4 scaling(Vector3 factors)
{
    return Matrix4(Vector4(factors.x, 0, 0, 0), Vector4(0, factors.y, 0, 0),
        Vector4(0, 0, factors.z, 0), Vector4(0, 0, 0, 1));
}

pure Matrix4 scaling(float factor)
{
    return scaling(Vector3(factor, factor, factor));
}

Matrix4 rotationX(float angle)
{
    const c = cosf(angle), s = sinf(angle);
    return Matrix4(Vector4(1, 0, 0, 0), Vector4(0, c, s, 0), Vector4(0, -s, c,
            0), Vector4(0, 0, 0, 1));
}

Matrix4 rotationY(float angle)
{
    const c = cosf(angle), s = sinf(angle);
    return Matrix4(Vector4(c, 0, -s, 0), Vector4(0, 1, 0, 0), Vector4(s, 0, c,
            0), Vector4(0, 0, 0, 1));
}

Matrix4 rotationZ(float angle)
{
    const c = cosf(angle), s = sinf(angle);
    return Matrix4(Vector4(c, s, 0, 0), Vector4(-s, c, 0, 0), Vector4(0, 0, 1,
            0), Vector4(0, 0, 0, 1));
}

Matrix4 rotation(Vector3 axis, float angle)
{
    axis = axis.normalized;
    if (axis == Vector3.init)
        return Matrix4.identity;
    const c = cosf(angle), s = sinf(angle), t = 1 - c, x = axis.x, y = axis.y, z = axis.z;
    return Matrix4(Vector4(x * x * t + c, y * x * t + z * s, z * x * t - y * s, 0),
        Vector4(x * y * t - z * s, y * y * t + c, z * y * t + x * s, 0),
        Vector4(x * z * t + y * s, y * z * t - x * s, z * z * t + c, 0), Vector4(0, 0, 0, 1));
}

Matrix4 rotation(float yaw, float pitch, float roll)
{
    return rotationZ(yaw) * rotationY(pitch) * rotationX(roll);
}

pure Matrix4 translated(Matrix4 base, Vector3 offset)
{
    return translation(offset) * base;
}

pure Matrix4 scaled(Matrix4 base, Vector3 factors)
{
    return scaling(factors) * base;
}

pure Matrix4 scaled(Matrix4 base, float factor)
{
    return scaling(factor) * base;
}

Matrix4 rotated(Matrix4 base, Vector3 axis, float angle)
{
    return rotation(axis, angle) * base;
}

pure Matrix4 orthographic(float left, float right, float bottom, float top, float near, float far)
{
    assert(right != left && top != bottom && far != near);
    return Matrix4(Vector4(2 / (right - left), 0, 0, 0), Vector4(0,
            2 / (top - bottom), 0, 0), Vector4(0, 0, -2 / (far - near), 0),
        Vector4(-(right + left) / (right - left),
            -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1));
}

pure Matrix4 orthographic2D(float left, float right, float bottom, float top)
{
    return orthographic(left, right, bottom, top, -1, 1);
}

pure Matrix4 screenProjection(float width, float height)
{
    assert(width > 0 && height > 0);
    return orthographic2D(0, width, height, 0);
}

Matrix4 perspective(float verticalFov, float aspect, float near, float far)
{
    assert(verticalFov > 0 && aspect > 0 && near > 0 && far > near);
    const f = 1 / tanf(verticalFov / 2);
    return Matrix4(Vector4(f / aspect, 0, 0, 0), Vector4(0, f, 0, 0),
        Vector4(0, 0, (far + near) / (near - far), -1), Vector4(0, 0,
            (2 * far * near) / (near - far), 0));
}

Matrix4 lookAt(Vector3 eye, Vector3 target, Vector3 up)
{
    const forward = (target - eye).normalized;
    const side = cross(forward, up).normalized;
    const correctedUp = cross(side, forward);
    return Matrix4(Vector4(side.x, correctedUp.x, -forward.x, 0),
        Vector4(side.y, correctedUp.y, -forward.y, 0), Vector4(side.z,
            correctedUp.z, -forward.z, 0), Vector4(-dot(side, eye),
            -dot(correctedUp, eye), dot(forward, eye), 1));
}

private pure bool close(float a, float b, float epsilon = 0.0001f)
{
    const d = a - b;
    return d < epsilon && d > -epsilon;
}

@system unittest
{
    const identity = Matrix4.identity;
    assert(identity * Vector4(1, 2, 3, 1) == Vector4(1, 2, 3, 1));
    assert(translation(Vector3(2, 3, 4)) * Vector4(1, 1, 1, 1) == Vector4(3, 4, 5, 1));
    Matrix3 inverse;
    const m = Matrix3(Vector3(2, 0, 0), Vector3(0, 4, 0), Vector3(0, 0, 5));
    assert(m.tryInverse(&inverse));
    assert(close((m * inverse).c0.x, 1) && close((m * inverse).c1.y, 1));
    assert(!Matrix3.init.tryInverse(&inverse));
    Matrix4 generalInverse;
    const general = Matrix4(Vector4(1, 2, 3, 4), Vector4(0, 1, 4, 2),
        Vector4(5, 6, 0, 1), Vector4(1, 0, 2, 1));
    assert(general.tryInverse(&generalInverse));
    const generalIdentity = general * generalInverse;
    assert(close(generalIdentity.c0.x, 1) && close(generalIdentity.c1.y, 1)
            && close(generalIdentity.c2.z, 1) && close(generalIdentity.c3.w, 1));
    Matrix4 affineInverse;
    const transform = translation(Vector3(2, 3, 4)) * scaling(Vector3(2, 3, 4));
    assert(transform.tryAffineInverse(&affineInverse));
    const restored = affineInverse * (transform * Vector4(1, 2, 3, 1));
    assert(close(restored.x, 1) && close(restored.y, 2) && close(restored.z, 3));
}
