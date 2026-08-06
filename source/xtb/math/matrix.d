module xtb.math.matrix;

@safe nothrow @nogc:

import core.stdc.math : cosf, sinf, tanf;
version (XTB_Checked)
    import xtb.core.panic : require;
import xtb.math.scalar : pi;
import xtb.math.vector : Vector2, Vector3, Vector4, cross, dot, isFinite,
    length, normalized, withW, xyz;

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

enum float inverseRelativeTolerance = 8 * float.epsilon;

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

@system bool tryInverse(Matrix2 m, Matrix2* output)
{
    version (XTB_Checked)
        require(output !is null, "Matrix2 inverse output pointer is null");
    if (!finite(m))
        return false;
    const scale = largestMagnitude(m);
    if (scale == 0)
        return false;
    const normalized = m * (1 / scale);
    const d = normalized.determinant;
    if (absolute(d) <= inverseRelativeTolerance)
        return false;
    *output = Matrix2(
        Vector2(normalized.c1.y, -normalized.c0.y),
        Vector2(-normalized.c1.x, normalized.c0.x),
    ) * (1 / (d * scale));
    return true;
}

@system bool tryInverse(Matrix3 m, Matrix3* output)
{
    version (XTB_Checked)
        require(output !is null, "Matrix3 inverse output pointer is null");
    if (!finite(m))
        return false;
    const scale = largestMagnitude(m);
    if (scale == 0)
        return false;
    const normalized = m * (1 / scale);
    const d = normalized.determinant;
    if (absolute(d) <= inverseRelativeTolerance)
        return false;
    *output = Matrix3(
        cross(normalized.c1, normalized.c2),
        cross(normalized.c2, normalized.c0),
        cross(normalized.c0, normalized.c1),
    ).transposed * (1 / (d * scale));
    return true;
}

@system bool tryInverse(Matrix4 m, Matrix4* output)
{
    version (XTB_Checked)
        require(output !is null, "Matrix4 inverse output pointer is null");
    if (!finite(m))
        return false;
    const scale = largestMagnitude(m);
    if (scale == 0)
        return false;
    const inverseScale = 1 / scale;
    float[8][4] rows;
    rows[0] = [
        m.c0.x * inverseScale, m.c1.x * inverseScale,
        m.c2.x * inverseScale, m.c3.x * inverseScale, 1, 0, 0, 0
    ];
    rows[1] = [
        m.c0.y * inverseScale, m.c1.y * inverseScale,
        m.c2.y * inverseScale, m.c3.y * inverseScale, 0, 1, 0, 0
    ];
    rows[2] = [
        m.c0.z * inverseScale, m.c1.z * inverseScale,
        m.c2.z * inverseScale, m.c3.z * inverseScale, 0, 0, 1, 0
    ];
    rows[3] = [
        m.c0.w * inverseScale, m.c1.w * inverseScale,
        m.c2.w * inverseScale, m.c3.w * inverseScale, 0, 0, 0, 1
    ];
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
        if (pivotMagnitude <= inverseRelativeTolerance)
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
        Vector4(rows[0][7], rows[1][7], rows[2][7], rows[3][7])) * inverseScale;
    return true;
}

private pure float absolute(float value)
{
    return value < 0 ? -value : value;
}

private pure bool finite(float value)
{
    return value == value && value >= -float.max && value <= float.max;
}

private pure bool finite(Matrix2 value)
{
    return value.c0.isFinite && value.c1.isFinite;
}

private pure bool finite(Matrix3 value)
{
    return value.c0.isFinite && value.c1.isFinite && value.c2.isFinite;
}

private pure bool finite(Matrix4 value)
{
    return value.c0.isFinite && value.c1.isFinite &&
        value.c2.isFinite && value.c3.isFinite;
}

private pure float maximum(float left, float right)
{
    return left > right ? left : right;
}

private pure float largestMagnitude(Matrix2 value)
{
    float result;
    result = maximum(result, absolute(value.c0.x));
    result = maximum(result, absolute(value.c0.y));
    result = maximum(result, absolute(value.c1.x));
    result = maximum(result, absolute(value.c1.y));
    return result;
}

private pure float largestMagnitude(Matrix3 value)
{
    float result;
    result = maximum(result, absolute(value.c0.x));
    result = maximum(result, absolute(value.c0.y));
    result = maximum(result, absolute(value.c0.z));
    result = maximum(result, absolute(value.c1.x));
    result = maximum(result, absolute(value.c1.y));
    result = maximum(result, absolute(value.c1.z));
    result = maximum(result, absolute(value.c2.x));
    result = maximum(result, absolute(value.c2.y));
    result = maximum(result, absolute(value.c2.z));
    return result;
}

private pure float largestMagnitude(Matrix4 value)
{
    float result = largestMagnitude(Matrix3(
            value.c0.xyz,
            value.c1.xyz,
            value.c2.xyz,
    ));
    result = maximum(result, absolute(value.c0.w));
    result = maximum(result, absolute(value.c1.w));
    result = maximum(result, absolute(value.c2.w));
    result = maximum(result, absolute(value.c3.x));
    result = maximum(result, absolute(value.c3.y));
    result = maximum(result, absolute(value.c3.z));
    result = maximum(result, absolute(value.c3.w));
    return result;
}

pure bool isAffine(Matrix4 m)
{
    return m.c0.w == 0 && m.c1.w == 0 && m.c2.w == 0 && m.c3.w == 1;
}

@system bool tryAffineInverse(Matrix4 m, Matrix4* output)
{
    version (XTB_Checked)
        require(output !is null, "affine inverse output pointer is null");
    if (!finite(m) || !m.isAffine)
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
    version (XTB_Checked)
        require(finite(angle), "rotation angle must be finite");
    const c = cosf(angle), s = sinf(angle);
    return Matrix4(Vector4(1, 0, 0, 0), Vector4(0, c, s, 0), Vector4(0, -s, c,
            0), Vector4(0, 0, 0, 1));
}

Matrix4 rotationY(float angle)
{
    version (XTB_Checked)
        require(finite(angle), "rotation angle must be finite");
    const c = cosf(angle), s = sinf(angle);
    return Matrix4(Vector4(c, 0, -s, 0), Vector4(0, 1, 0, 0), Vector4(s, 0, c,
            0), Vector4(0, 0, 0, 1));
}

Matrix4 rotationZ(float angle)
{
    version (XTB_Checked)
        require(finite(angle), "rotation angle must be finite");
    const c = cosf(angle), s = sinf(angle);
    return Matrix4(Vector4(c, s, 0, 0), Vector4(-s, c, 0, 0), Vector4(0, 0, 1,
            0), Vector4(0, 0, 0, 1));
}

Matrix4 rotation(Vector3 axis, float angle)
{
    version (XTB_Checked)
        require(axis.isFinite && finite(angle),
            "rotation axis and angle must be finite");
    axis = axis.normalized;
    if (axis == Vector3.init)
        return Matrix4.identity;
    const c = cosf(angle), s = sinf(angle), t = 1 - c, x = axis.x, y = axis.y, z = axis.z;
    return Matrix4(Vector4(x * x * t + c, y * x * t + z * s, z * x * t - y * s, 0),
        Vector4(x * y * t - z * s, y * y * t + c, z * y * t + x * s, 0),
        Vector4(x * z * t + y * s, y * z * t - x * s, z * z * t + c, 0), Vector4(0, 0, 0, 1));
}

Matrix4 rotationYawPitchRoll(float yaw, float pitch, float roll)
{
    version (XTB_Checked)
        require(finite(yaw) && finite(pitch) && finite(roll),
            "yaw, pitch, and roll must be finite");
    return rotationY(-yaw) * rotationX(pitch) * rotationZ(roll);
}

pure Matrix4 preTranslated(Matrix4 base, Vector3 offset)
{
    return translation(offset) * base;
}

pure Matrix4 postTranslated(Matrix4 base, Vector3 offset)
{
    return base * translation(offset);
}

pure Matrix4 preScaled(Matrix4 base, Vector3 factors)
{
    return scaling(factors) * base;
}

pure Matrix4 postScaled(Matrix4 base, Vector3 factors)
{
    return base * scaling(factors);
}

pure Matrix4 preScaled(Matrix4 base, float factor)
{
    return scaling(factor) * base;
}

pure Matrix4 postScaled(Matrix4 base, float factor)
{
    return base * scaling(factor);
}

Matrix4 preRotated(Matrix4 base, Vector3 axis, float angle)
{
    return rotation(axis, angle) * base;
}

Matrix4 postRotated(Matrix4 base, Vector3 axis, float angle)
{
    return base * rotation(axis, angle);
}

Matrix4 orthographic(float left, float right, float bottom, float top, float near, float far)
{
    version (XTB_Checked)
    {
        require(finite(left) && finite(right) && finite(bottom) && finite(top) &&
                finite(near) && finite(far), "orthographic bounds must be finite");
        require(right != left && top != bottom && far != near,
            "orthographic bounds must have nonzero extent");
    }
    return Matrix4(Vector4(2 / (right - left), 0, 0, 0), Vector4(0,
            2 / (top - bottom), 0, 0), Vector4(0, 0, -2 / (far - near), 0),
        Vector4(-(right + left) / (right - left),
            -(top + bottom) / (top - bottom), -(far + near) / (far - near), 1));
}

Matrix4 orthographic2D(float left, float right, float bottom, float top)
{
    return orthographic(left, right, bottom, top, -1, 1);
}

Matrix4 screenProjection(float width, float height)
{
    version (XTB_Checked)
        require(finite(width) && finite(height) && width > 0 && height > 0,
            "screen dimensions must be positive and finite");
    return orthographic2D(0, width, height, 0);
}

Matrix4 perspective(float verticalFov, float aspect, float near, float far)
{
    version (XTB_Checked)
    {
        require(finite(verticalFov) && finite(aspect) && finite(near) && finite(far),
            "perspective arguments must be finite");
        require(verticalFov > 0 && verticalFov < pi,
            "perspective field of view must be between zero and pi");
        require(aspect > 0 && near > 0 && far > near,
            "perspective aspect and clipping planes are invalid");
    }
    const f = 1 / tanf(verticalFov / 2);
    return Matrix4(Vector4(f / aspect, 0, 0, 0), Vector4(0, f, 0, 0),
        Vector4(0, 0, (far + near) / (near - far), -1), Vector4(0, 0,
            (2 * far * near) / (near - far), 0));
}

@system bool tryLookAt(
    Vector3 eye,
    Vector3 target,
    Vector3 up,
    Matrix4* output,
)
{
    version (XTB_Checked)
        require(output !is null, "look-at output pointer is null");
    if (!eye.isFinite || !target.isFinite || !up.isFinite)
        return false;
    const forward = (target - eye).normalized;
    if (forward == Vector3.init)
        return false;
    const unitUp = up.normalized;
    if (unitUp == Vector3.init)
        return false;
    const sideVector = cross(forward, unitUp);
    const sideLength = sideVector.length;
    if (!finite(sideLength) || sideLength <= inverseRelativeTolerance)
        return false;
    const side = sideVector / sideLength;
    const correctedUp = cross(side, forward);
    *output = Matrix4(Vector4(side.x, correctedUp.x, -forward.x, 0),
        Vector4(side.y, correctedUp.y, -forward.y, 0), Vector4(side.z,
            correctedUp.z, -forward.z, 0), Vector4(-dot(side, eye),
            -dot(correctedUp, eye), dot(forward, eye), 1));
    return true;
}

@trusted Matrix4 lookAt(Vector3 eye, Vector3 target, Vector3 up)
{
    Matrix4 result;
    const succeeded = tryLookAt(eye, target, up, &result);
    version (XTB_Checked)
        require(succeeded, "look-at vectors are non-finite or degenerate");
    return result;
}

private pure bool close(float a, float b, float epsilon = 0.0001f)
{
    const d = a - b;
    return d < epsilon && d > -epsilon;
}

private pure bool close(Vector4 a, Vector4 b, float epsilon = 0.0001f)
{
    return close(a.x, b.x, epsilon) && close(a.y, b.y, epsilon) &&
        close(a.z, b.z, epsilon) && close(a.w, b.w, epsilon);
}

private pure bool close(Matrix4 a, Matrix4 b, float epsilon = 0.0001f)
{
    return close(a.c0, b.c0, epsilon) && close(a.c1, b.c1, epsilon) &&
        close(a.c2, b.c2, epsilon) && close(a.c3, b.c3, epsilon);
}

@system unittest
{
    const identity = Matrix4.identity;
    assert(identity * Vector4(1, 2, 3, 1) == Vector4(1, 2, 3, 1));
    assert(translation(Vector3(2, 3, 4)) * Vector4(1, 1, 1, 1) == Vector4(3, 4, 5, 1));
    Matrix3 inverse;
    const m = Matrix3(Vector3(2, 0, 0), Vector3(0, 4, 0), Vector3(0, 0, 5));
    assert(m.tryInverse(&inverse));
    const matrix3Identity = m * inverse;
    assert(close(matrix3Identity.c0.withW(0), Vector4(1, 0, 0, 0)));
    assert(close(matrix3Identity.c1.withW(0), Vector4(0, 1, 0, 0)));
    assert(close(matrix3Identity.c2.withW(0), Vector4(0, 0, 1, 0)));

    Matrix2 matrix2Inverse = Matrix2.identity;
    const nearSingular = Matrix2(
        Vector2(1, 0),
        Vector2(0, inverseRelativeTolerance / 2),
    );
    assert(!nearSingular.tryInverse(&matrix2Inverse));
    assert(matrix2Inverse == Matrix2.identity);
    const veryLarge = Matrix2(
        Vector2(float.max, 0),
        Vector2(0, float.max),
    );
    assert(veryLarge.tryInverse(&matrix2Inverse));
    const matrix2Identity = veryLarge * matrix2Inverse;
    assert(close(matrix2Identity.c0.x, 1) && close(matrix2Identity.c0.y, 0));
    assert(close(matrix2Identity.c1.x, 0) && close(matrix2Identity.c1.y, 1));

    inverse = Matrix3.identity;
    assert(!Matrix3.init.tryInverse(&inverse));
    assert(inverse == Matrix3.identity);
    Matrix4 generalInverse;
    const general = Matrix4(Vector4(1, 2, 3, 4), Vector4(0, 1, 4, 2),
        Vector4(5, 6, 0, 1), Vector4(1, 0, 2, 1));
    assert(general.tryInverse(&generalInverse));
    const generalIdentity = general * generalInverse;
    assert(close(generalIdentity, identity, 0.001f));
    Matrix4 affineInverse;
    const transform = translation(Vector3(2, 3, 4)) * scaling(Vector3(2, 3, 4));
    assert(transform.tryAffineInverse(&affineInverse));
    const restored = affineInverse * (transform * Vector4(1, 2, 3, 1));
    assert(close(restored.x, 1) && close(restored.y, 2) && close(restored.z, 3));

    Matrix4 camera = Matrix4.identity;
    assert(!tryLookAt(Vector3.init, Vector3.init, Vector3(0, 1, 0), &camera));
    assert(camera == Matrix4.identity);
    assert(!tryLookAt(Vector3.init, Vector3(0, 0, -1),
            Vector3(0, 0, -2), &camera));
    assert(camera == Matrix4.identity);
    assert(tryLookAt(Vector3(0, 0, 3), Vector3.init,
            Vector3(0, 1, 0), &camera));
    assert(camera.finite);

    import xtb.math.random : Random;
    import xtb.math.scalar : radians;
    import xtb.math.vector : directionFromDegrees;

    const yaw = 35.0f, pitch = -20.0f;
    const expectedDirection = directionFromDegrees(yaw, pitch);
    const rotatedDirection = (rotationYawPitchRoll(
            radians(yaw), radians(pitch), 0,
    ) * Vector4(0, 0, -1, 0)).xyz;
    assert(close(rotatedDirection.withW(0), expectedDirection.withW(0)));

    const base = scaling(2);
    const pre = base.preTranslated(Vector3(1, 0, 0));
    const post = base.postTranslated(Vector3(1, 0, 0));
    assert(pre * Vector4(0, 0, 0, 1) == Vector4(1, 0, 0, 1));
    assert(post * Vector4(0, 0, 0, 1) == Vector4(2, 0, 0, 1));

    Random random = Random.seeded(0xCAFE, 7);
    foreach (_; 0 .. 64)
    {
        const offset = Vector3(
            random.between(-10, 10),
            random.between(-10, 10),
            random.between(-10, 10),
        );
        const factors = Vector3(
            random.between(0.5f, 3),
            random.between(0.5f, 3),
            random.between(0.5f, 3),
        );
        Vector3 axis = Vector3(
            random.between(-1, 1),
            random.between(-1, 1),
            random.between(-1, 1),
        );
        if (axis == Vector3.init)
            axis.x = 1;
        const value = translation(offset) *
            rotation(axis, random.between(-pi, pi)) * scaling(factors);
        Matrix4 valueInverse;
        assert(value.tryInverse(&valueInverse));
        assert(close(value * valueInverse, identity, 0.002f));
        assert(value.tryAffineInverse(&valueInverse));
        assert(close(value * valueInverse, identity, 0.002f));
    }
}
