module xtb.math.matrix;

nothrow @nogc @safe:

import xtb.math.quaternion;
import xtb.math.scalar;
import xtb.math.vector;
import xtb.panic;
import xtb.types;

struct Matrix2
{
    nothrow @nogc @safe:

    Vector2 c0;
    Vector2 c1;

    static Matrix2 identity() pure
    {
        return Matrix2(Vector2(1, 0), Vector2(0, 1));
    }

    Matrix2 opBinary(string op : "*")(f32 scalar) const pure
    {
        return Matrix2(this.c0 * scalar, this.c1 * scalar);
    }

    Vector2 opBinary(string op : "*")(Vector2 vector) const pure
    {
        return this.c0 * vector.x + this.c1 * vector.y;
    }

    Matrix2 opBinary(string op : "*")(Matrix2 other) const pure
    {
        return Matrix2(this * other.c0, this * other.c1);
    }

    Matrix2 transposed() const pure
    {
        return Matrix2(
            Vector2(this.c0.x, this.c1.x),
            Vector2(this.c0.y, this.c1.y),
        );
    }

    f32 determinant() const pure
    {
        return this.c0.x * this.c1.y - this.c1.x * this.c0.y;
    }

    private bool is_finite() const pure
    {
        return this.c0.is_finite && this.c1.is_finite;
    }

    private f32 largest_magnitude() const pure
    {
        f32 result = 0;
        result = maximum(result, absolute(this.c0.x));
        result = maximum(result, absolute(this.c0.y));
        result = maximum(result, absolute(this.c1.x));
        result = maximum(result, absolute(this.c1.y));
        return result;
    }

    /// `output` must not be null.
    ///
    /// On failure, `output` remains unchanged.
    bool try_inverse(Matrix2* output) const @system
    {
        require(output !is null, "Matrix2 inverse output pointer is null");
        if (!this.is_finite) return false;

        const scale = this.largest_magnitude;
        if (scale == 0) return false;

        const normalized = this * (1 / scale);
        const determinant = normalized.determinant;
        if (absolute(determinant) <= inverse_relative_tolerance) return false;

        *output = Matrix2(
            Vector2(normalized.c1.y, -normalized.c0.y),
            Vector2(-normalized.c1.x, normalized.c0.x),
        ) * (1 / (determinant * scale));
        return true;
    }
}

struct Matrix3
{
    nothrow @nogc @safe:

    Vector3 c0;
    Vector3 c1;
    Vector3 c2;

    static Matrix3 identity() pure
    {
        return Matrix3(
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, 0, 1),
        );
    }

    /// Creates a rotation matrix from a unit quaternion.
    static Matrix3 from_quaternion(Quaternion rotation)
    {
        require(rotation.is_unit, "rotation quaternion must be unit length");

        const xx = rotation.x * rotation.x;
        const yy = rotation.y * rotation.y;
        const zz = rotation.z * rotation.z;
        const xy = rotation.x * rotation.y;
        const xz = rotation.x * rotation.z;
        const yz = rotation.y * rotation.z;
        const wx = rotation.w * rotation.x;
        const wy = rotation.w * rotation.y;
        const wz = rotation.w * rotation.z;
        return Matrix3(
            Vector3(1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy)),
            Vector3(2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx)),
            Vector3(2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy)),
        );
    }

    Matrix3 opBinary(string op : "*")(f32 scalar) const pure
    {
        return Matrix3(this.c0 * scalar, this.c1 * scalar, this.c2 * scalar);
    }

    Vector3 opBinary(string op : "*")(Vector3 vector) const pure
    {
        return this.c0 * vector.x + this.c1 * vector.y + this.c2 * vector.z;
    }

    Matrix3 opBinary(string op : "*")(Matrix3 other) const pure
    {
        return Matrix3(this * other.c0, this * other.c1, this * other.c2);
    }

    Matrix3 transposed() const pure
    {
        return Matrix3(
            Vector3(this.c0.x, this.c1.x, this.c2.x),
            Vector3(this.c0.y, this.c1.y, this.c2.y),
            Vector3(this.c0.z, this.c1.z, this.c2.z),
        );
    }

    f32 determinant() const pure
    {
        return dot(this.c0, cross(this.c1, this.c2));
    }

    private bool is_finite() const pure
    {
        return this.c0.is_finite && this.c1.is_finite && this.c2.is_finite;
    }

    private f32 largest_magnitude() const pure
    {
        f32 result = 0;
        result = maximum(result, absolute(this.c0.x));
        result = maximum(result, absolute(this.c0.y));
        result = maximum(result, absolute(this.c0.z));
        result = maximum(result, absolute(this.c1.x));
        result = maximum(result, absolute(this.c1.y));
        result = maximum(result, absolute(this.c1.z));
        result = maximum(result, absolute(this.c2.x));
        result = maximum(result, absolute(this.c2.y));
        result = maximum(result, absolute(this.c2.z));
        return result;
    }

    /// `output` must not be null.
    ///
    /// On failure, `output` remains unchanged.
    bool try_inverse(Matrix3* output) const @system
    {
        require(output !is null, "Matrix3 inverse output pointer is null");
        if (!this.is_finite) return false;

        const scale = this.largest_magnitude;
        if (scale == 0) return false;

        const normalized = this * (1 / scale);
        const determinant = normalized.determinant;
        if (absolute(determinant) <= inverse_relative_tolerance) return false;

        *output = Matrix3(
            cross(normalized.c1, normalized.c2),
            cross(normalized.c2, normalized.c0),
            cross(normalized.c0, normalized.c1),
        ).transposed * (1 / (determinant * scale));
        return true;
    }
}

struct Matrix4
{
    nothrow @nogc @safe:

    Vector4 c0;
    Vector4 c1;
    Vector4 c2;
    Vector4 c3;

    static Matrix4 identity() pure
    {
        return Matrix4(
            Vector4(1, 0, 0, 0),
            Vector4(0, 1, 0, 0),
            Vector4(0, 0, 1, 0),
            Vector4(0, 0, 0, 1),
        );
    }

    /// Creates an affine rotation matrix from a unit quaternion.
    static Matrix4 from_quaternion(Quaternion rotation)
    {
        const linear = Matrix3.from_quaternion(rotation);
        return Matrix4(
            linear.c0.with_w(0),
            linear.c1.with_w(0),
            linear.c2.with_w(0),
            Vector4(0, 0, 0, 1),
        );
    }

    Matrix4 opBinary(string op : "*")(f32 scalar) const pure
    {
        return Matrix4(
            this.c0 * scalar,
            this.c1 * scalar,
            this.c2 * scalar,
            this.c3 * scalar,
        );
    }

    Vector4 opBinary(string op : "*")(Vector4 vector) const pure
    {
        return this.c0 * vector.x
            + this.c1 * vector.y
            + this.c2 * vector.z
            + this.c3 * vector.w;
    }

    Matrix4 opBinary(string op : "*")(Matrix4 other) const pure
    {
        return Matrix4(
            this * other.c0,
            this * other.c1,
            this * other.c2,
            this * other.c3,
        );
    }

    Matrix4 transposed() const pure
    {
        return Matrix4(
            Vector4(this.c0.x, this.c1.x, this.c2.x, this.c3.x),
            Vector4(this.c0.y, this.c1.y, this.c2.y, this.c3.y),
            Vector4(this.c0.z, this.c1.z, this.c2.z, this.c3.z),
            Vector4(this.c0.w, this.c1.w, this.c2.w, this.c3.w),
        );
    }

    f32 determinant() const pure
    {
        const m00 = this.c0.x;
        const m01 = this.c1.x;
        const m02 = this.c2.x;
        const m03 = this.c3.x;
        const m10 = this.c0.y;
        const m11 = this.c1.y;
        const m12 = this.c2.y;
        const m13 = this.c3.y;
        const m20 = this.c0.z;
        const m21 = this.c1.z;
        const m22 = this.c2.z;
        const m23 = this.c3.z;
        const m30 = this.c0.w;
        const m31 = this.c1.w;
        const m32 = this.c2.w;
        const m33 = this.c3.w;

        return m00 * (
            m11 * (m22 * m33 - m23 * m32)
                - m12 * (m21 * m33 - m23 * m31)
                + m13 * (m21 * m32 - m22 * m31)
        ) - m01 * (
            m10 * (m22 * m33 - m23 * m32)
                - m12 * (m20 * m33 - m23 * m30)
                + m13 * (m20 * m32 - m22 * m30)
        ) + m02 * (
            m10 * (m21 * m33 - m23 * m31)
                - m11 * (m20 * m33 - m23 * m30)
                + m13 * (m20 * m31 - m21 * m30)
        ) - m03 * (
            m10 * (m21 * m32 - m22 * m31)
                - m11 * (m20 * m32 - m22 * m30)
                + m12 * (m20 * m31 - m21 * m30)
        );
    }

    private bool is_finite() const pure
    {
        return this.c0.is_finite
            && this.c1.is_finite
            && this.c2.is_finite
            && this.c3.is_finite;
    }

    private f32 largest_magnitude() const pure
    {
        f32 result = Matrix3(this.c0.xyz, this.c1.xyz, this.c2.xyz).largest_magnitude;
        result = maximum(result, absolute(this.c0.w));
        result = maximum(result, absolute(this.c1.w));
        result = maximum(result, absolute(this.c2.w));
        result = maximum(result, absolute(this.c3.x));
        result = maximum(result, absolute(this.c3.y));
        result = maximum(result, absolute(this.c3.z));
        result = maximum(result, absolute(this.c3.w));
        return result;
    }

    /// `output` must not be null.
    ///
    /// On failure, `output` remains unchanged.
    bool try_inverse(Matrix4* output) const @system
    {
        require(output !is null, "Matrix4 inverse output pointer is null");
        if (!this.is_finite) return false;

        const scale = this.largest_magnitude;
        if (scale == 0) return false;

        const inverse_scale = 1 / scale;
        f32[8][4] rows;
        rows[0] = [
            this.c0.x * inverse_scale,
            this.c1.x * inverse_scale,
            this.c2.x * inverse_scale,
            this.c3.x * inverse_scale,
            1,
            0,
            0,
            0,
        ];
        rows[1] = [
            this.c0.y * inverse_scale,
            this.c1.y * inverse_scale,
            this.c2.y * inverse_scale,
            this.c3.y * inverse_scale,
            0,
            1,
            0,
            0,
        ];
        rows[2] = [
            this.c0.z * inverse_scale,
            this.c1.z * inverse_scale,
            this.c2.z * inverse_scale,
            this.c3.z * inverse_scale,
            0,
            0,
            1,
            0,
        ];
        rows[3] = [
            this.c0.w * inverse_scale,
            this.c1.w * inverse_scale,
            this.c2.w * inverse_scale,
            this.c3.w * inverse_scale,
            0,
            0,
            0,
            1,
        ];

        foreach (column; 0 .. 4)
        {
            usize pivot = column;
            f32 pivot_magnitude = absolute(rows[pivot][column]);
            foreach (row; column + 1 .. 4)
            {
                const magnitude = absolute(rows[row][column]);
                if (magnitude > pivot_magnitude)
                {
                    pivot = row;
                    pivot_magnitude = magnitude;
                }
            }

            if (pivot_magnitude <= inverse_relative_tolerance) return false;

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
                if (row == column) continue;

                const factor = rows[row][column];
                foreach (entry; 0 .. 8)
                    rows[row][entry] -= factor * rows[column][entry];
            }
        }

        *output = Matrix4(
            Vector4(rows[0][4], rows[1][4], rows[2][4], rows[3][4]),
            Vector4(rows[0][5], rows[1][5], rows[2][5], rows[3][5]),
            Vector4(rows[0][6], rows[1][6], rows[2][6], rows[3][6]),
            Vector4(rows[0][7], rows[1][7], rows[2][7], rows[3][7]),
        ) * inverse_scale;
        return true;
    }

    bool is_affine() const pure
    {
        return this.c0.w == 0 && this.c1.w == 0 && this.c2.w == 0 && this.c3.w == 1;
    }

    /// Transforms a point, including translation.
    ///
    /// This matrix must be affine.
    Vector3 transform_point(Vector3 point) const
    {
        require(this.is_affine, "point transform matrix must be affine");
        return (this * point.with_w(1)).xyz;
    }

    /// Transforms a direction, excluding translation.
    ///
    /// This matrix must be affine.
    Vector3 transform_direction(Vector3 direction) const
    {
        require(this.is_affine, "direction transform matrix must be affine");
        return (this * direction.with_w(0)).xyz;
    }

    /// `output` must not be null.
    ///
    /// Returns false if this matrix is non-affine or its linear transform is singular.
    ///
    /// On failure, `output` remains unchanged.
    bool try_normal_matrix(scope Matrix3* output) const @system
    {
        require(output !is null, "normal matrix output pointer is null");
        if (!this.is_affine) return false;

        Matrix3 linear_inverse;
        if (!Matrix3(this.c0.xyz, this.c1.xyz, this.c2.xyz).try_inverse(&linear_inverse))
            return false;

        *output = linear_inverse.transposed;
        return true;
    }

    /// `output` must not be null.
    ///
    /// On failure, `output` remains unchanged.
    bool try_affine_inverse(Matrix4* output) const @system
    {
        require(output !is null, "affine inverse output pointer is null");
        if (!this.is_finite || !this.is_affine) return false;

        Matrix3 linear_inverse;
        if (!Matrix3(this.c0.xyz, this.c1.xyz, this.c2.xyz).try_inverse(&linear_inverse))
            return false;

        const translation = -(linear_inverse * this.c3.xyz);
        *output = Matrix4(
            linear_inverse.c0.with_w(0),
            linear_inverse.c1.with_w(0),
            linear_inverse.c2.with_w(0),
            translation.with_w(1),
        );
        return true;
    }

    Matrix4 pre_translated(Vector3 offset) const pure
    {
        return translation(offset) * this;
    }

    Matrix4 post_translated(Vector3 offset) const pure
    {
        return this * translation(offset);
    }

    Matrix4 pre_scaled(Vector3 factors) const pure
    {
        return scaling(factors) * this;
    }

    Matrix4 post_scaled(Vector3 factors) const pure
    {
        return this * scaling(factors);
    }

    Matrix4 pre_scaled(f32 factor) const pure
    {
        return scaling(factor) * this;
    }

    Matrix4 post_scaled(f32 factor) const pure
    {
        return this * scaling(factor);
    }

    /// Returns this matrix pre-multiplied by a rotation of `angle` radians around `axis`.
    Matrix4 pre_rotated(Vector3 axis, f32 angle) const
    {
        return rotation(axis, angle) * this;
    }

    /// Returns this matrix post-multiplied by a rotation of `angle` radians around `axis`.
    Matrix4 post_rotated(Vector3 axis, f32 angle) const
    {
        return this * rotation(axis, angle);
    }
}

static assert(Matrix2.sizeof == 4 * f32.sizeof);
static assert(Matrix3.sizeof == 9 * f32.sizeof);
static assert(Matrix4.sizeof == 16 * f32.sizeof);

private enum f32 inverse_relative_tolerance = 8 * f32.epsilon;

private f32 absolute(f32 value) pure
{
    return value < 0 ? -value : value;
}

private f32 maximum(f32 left, f32 right) pure
{
    return left > right ? left : right;
}

Matrix4 translation(Vector3 offset) pure
{
    Matrix4 result = Matrix4.identity;
    result.c3 = offset.with_w(1);
    return result;
}

Matrix4 scaling(Vector3 factors) pure
{
    return Matrix4(
        Vector4(factors.x, 0, 0, 0),
        Vector4(0, factors.y, 0, 0),
        Vector4(0, 0, factors.z, 0),
        Vector4(0, 0, 0, 1),
    );
}

Matrix4 scaling(f32 factor) pure
{
    return scaling(Vector3(factor, factor, factor));
}

/// Creates a translation-rotation-scale matrix that applies scale, then rotation, then translation.
///
/// `orientation` must be a unit quaternion and all components must be finite.
Matrix4 trs(Vector3 position, Quaternion orientation, Vector3 scale)
{
    require(
        position.is_finite && orientation.is_unit && scale.is_finite,
        "TRS components must be finite and rotation must be unit length",
    );

    const rotation_matrix = Matrix3.from_quaternion(orientation);
    return Matrix4(
        (rotation_matrix.c0 * scale.x).with_w(0),
        (rotation_matrix.c1 * scale.y).with_w(0),
        (rotation_matrix.c2 * scale.z).with_w(0),
        position.with_w(1),
    );
}

/// Creates a rotation of `angle` radians around positive X.
Matrix4 rotation_x(f32 angle)
{
    require(angle.is_finite, "rotation angle must be finite");

    const cosine = cos(angle);
    const sine = sin(angle);
    return Matrix4(
        Vector4(1, 0, 0, 0),
        Vector4(0, cosine, sine, 0),
        Vector4(0, -sine, cosine, 0),
        Vector4(0, 0, 0, 1),
    );
}

/// Creates a rotation of `angle` radians around positive Y.
Matrix4 rotation_y(f32 angle)
{
    require(angle.is_finite, "rotation angle must be finite");

    const cosine = cos(angle);
    const sine = sin(angle);
    return Matrix4(
        Vector4(cosine, 0, -sine, 0),
        Vector4(0, 1, 0, 0),
        Vector4(sine, 0, cosine, 0),
        Vector4(0, 0, 0, 1),
    );
}

/// Creates a rotation of `angle` radians around positive Z.
Matrix4 rotation_z(f32 angle)
{
    require(angle.is_finite, "rotation angle must be finite");

    const cosine = cos(angle);
    const sine = sin(angle);
    return Matrix4(
        Vector4(cosine, sine, 0, 0),
        Vector4(-sine, cosine, 0, 0),
        Vector4(0, 0, 1, 0),
        Vector4(0, 0, 0, 1),
    );
}

/// Creates a rotation of `angle` radians around `axis`.
Matrix4 rotation(Vector3 axis, f32 angle)
{
    require(axis.is_finite && angle.is_finite, "rotation axis and angle must be finite");

    axis = axis.normalized;
    if (axis == Vector3.init) return Matrix4.identity;

    const cosine = cos(angle);
    const sine = sin(angle);
    const one_minus_cosine = 1 - cosine;
    const axis_x = axis.x;
    const axis_y = axis.y;
    const axis_z = axis.z;
    return Matrix4(
        Vector4(
            axis_x * axis_x * one_minus_cosine + cosine,
            axis_y * axis_x * one_minus_cosine + axis_z * sine,
            axis_z * axis_x * one_minus_cosine - axis_y * sine,
            0,
        ),
        Vector4(
            axis_x * axis_y * one_minus_cosine - axis_z * sine,
            axis_y * axis_y * one_minus_cosine + cosine,
            axis_z * axis_y * one_minus_cosine + axis_x * sine,
            0,
        ),
        Vector4(
            axis_x * axis_z * one_minus_cosine + axis_y * sine,
            axis_y * axis_z * one_minus_cosine - axis_x * sine,
            axis_z * axis_z * one_minus_cosine + cosine,
            0,
        ),
        Vector4(0, 0, 0, 1),
    );
}

/// Creates a yaw-pitch-roll rotation from radian angles.
Matrix4 rotation_yaw_pitch_roll(f32 yaw, f32 pitch, f32 roll)
{
    require(
        yaw.is_finite && pitch.is_finite && roll.is_finite,
        "yaw, pitch, and roll must be finite",
    );
    return rotation_y(-yaw) * rotation_x(pitch) * rotation_z(roll);
}

Matrix4 orthographic(f32 left, f32 right, f32 bottom, f32 top, f32 near, f32 far)
{
    require(
        left.is_finite
            && right.is_finite
            && bottom.is_finite
            && top.is_finite
            && near.is_finite
            && far.is_finite,
        "orthographic bounds must be finite",
    );
    require(
        right != left && top != bottom && far != near,
        "orthographic bounds must have nonzero extent",
    );

    return Matrix4(
        Vector4(2 / (right - left), 0, 0, 0),
        Vector4(0, 2 / (top - bottom), 0, 0),
        Vector4(0, 0, -2 / (far - near), 0),
        Vector4(
            -(right + left) / (right - left),
            -(top + bottom) / (top - bottom),
            -(far + near) / (far - near),
            1,
        ),
    );
}

Matrix4 orthographic_2d(f32 left, f32 right, f32 bottom, f32 top)
{
    return orthographic(left, right, bottom, top, -1, 1);
}

Matrix4 screen_projection(f32 width, f32 height)
{
    require(
        width.is_finite && height.is_finite && width > 0 && height > 0,
        "screen dimensions must be positive and finite",
    );
    return orthographic_2d(0, width, height, 0);
}

/// Creates a perspective projection with `vertical_fov` specified in radians.
Matrix4 perspective(f32 vertical_fov, f32 aspect, f32 near, f32 far)
{
    require(
        vertical_fov.is_finite && aspect.is_finite && near.is_finite && far.is_finite,
        "perspective arguments must be finite",
    );
    require(
        vertical_fov > 0 && vertical_fov < pi,
        "perspective field of view must be between zero and pi",
    );
    require(
        aspect > 0 && near > 0 && far > near,
        "perspective aspect and clipping planes are invalid",
    );

    const focal_scale = 1 / tan(vertical_fov / 2);
    return Matrix4(
        Vector4(focal_scale / aspect, 0, 0, 0),
        Vector4(0, focal_scale, 0, 0),
        Vector4(0, 0, (far + near) / (near - far), -1),
        Vector4(0, 0, (2 * far * near) / (near - far), 0),
    );
}

/// `output` must not be null.
///
/// On failure, `output` remains unchanged.
bool try_look_at(Vector3 eye, Vector3 target, Vector3 up, Matrix4* output) @system
{
    require(output !is null, "look-at output pointer is null");
    if (!eye.is_finite || !target.is_finite || !up.is_finite) return false;

    const forward = (target - eye).normalized;
    if (forward == Vector3.init) return false;

    const unit_up = up.normalized;
    if (unit_up == Vector3.init) return false;

    const side_vector = cross(forward, unit_up);
    const side_length = side_vector.length;
    if (!side_length.is_finite || side_length <= inverse_relative_tolerance) return false;

    const side = side_vector / side_length;
    const corrected_up = cross(side, forward);
    *output = Matrix4(
        Vector4(side.x, corrected_up.x, -forward.x, 0),
        Vector4(side.y, corrected_up.y, -forward.y, 0),
        Vector4(side.z, corrected_up.z, -forward.z, 0),
        Vector4(-dot(side, eye), -dot(corrected_up, eye), dot(forward, eye), 1),
    );
    return true;
}

Matrix4 look_at(Vector3 eye, Vector3 target, Vector3 up) @trusted
{
    Matrix4 result;
    // The output pointer targets live local storage, satisfying `try_look_at`'s @system contract.
    const succeeded = try_look_at(eye, target, up, &result);
    require(succeeded, "look-at vectors are non-finite or degenerate");
    return result;
}

version (unittest)
{
    import xtb.math.random;

    private bool close(f32 left, f32 right, f32 epsilon = 0.0001f) pure
    {
        const difference = left - right;
        return difference < epsilon && difference > -epsilon;
    }

    private bool close(Vector4 left, Vector4 right, f32 epsilon = 0.0001f) pure
    {
        return close(left.x, right.x, epsilon)
            && close(left.y, right.y, epsilon)
            && close(left.z, right.z, epsilon)
            && close(left.w, right.w, epsilon);
    }

    private bool close(Matrix4 left, Matrix4 right, f32 epsilon = 0.0001f) pure
    {
        return close(left.c0, right.c0, epsilon)
            && close(left.c1, right.c1, epsilon)
            && close(left.c2, right.c2, epsilon)
            && close(left.c3, right.c3, epsilon);
    }
}

unittest
{
    const identity = Matrix4.identity;
    assert(identity * Vector4(1, 2, 3, 1) == Vector4(1, 2, 3, 1));
    assert(
        translation(Vector3(2, 3, 4)) * Vector4(1, 1, 1, 1)
            == Vector4(3, 4, 5, 1),
    );
}

@system unittest
{
    const identity = Matrix4.identity;

    Matrix3 inverse;
    const matrix3 = Matrix3(
        Vector3(2, 0, 0),
        Vector3(0, 4, 0),
        Vector3(0, 0, 5),
    );
    assert(matrix3.try_inverse(&inverse));
    const matrix3_identity = matrix3 * inverse;
    assert(close(matrix3_identity.c0.with_w(0), Vector4(1, 0, 0, 0)));
    assert(close(matrix3_identity.c1.with_w(0), Vector4(0, 1, 0, 0)));
    assert(close(matrix3_identity.c2.with_w(0), Vector4(0, 0, 1, 0)));

    Matrix2 matrix2_inverse = Matrix2.identity;
    const near_singular = Matrix2(
        Vector2(1, 0),
        Vector2(0, inverse_relative_tolerance / 2),
    );
    assert(!near_singular.try_inverse(&matrix2_inverse));
    assert(matrix2_inverse == Matrix2.identity);

    const very_large = Matrix2(
        Vector2(f32.max, 0),
        Vector2(0, f32.max),
    );
    assert(very_large.try_inverse(&matrix2_inverse));
    const matrix2_identity = very_large * matrix2_inverse;
    assert(close(matrix2_identity.c0.x, 1) && close(matrix2_identity.c0.y, 0));
    assert(close(matrix2_identity.c1.x, 0) && close(matrix2_identity.c1.y, 1));

    inverse = Matrix3.identity;
    assert(!Matrix3.init.try_inverse(&inverse));
    assert(inverse == Matrix3.identity);

    Matrix4 general_inverse;
    const general = Matrix4(
        Vector4(1, 2, 3, 4),
        Vector4(0, 1, 4, 2),
        Vector4(5, 6, 0, 1),
        Vector4(1, 0, 2, 1),
    );
    assert(general.try_inverse(&general_inverse));
    const general_identity = general * general_inverse;
    assert(close(general_identity, identity, 0.001f));

    Matrix4 affine_inverse;
    const transform = translation(Vector3(2, 3, 4)) * scaling(Vector3(2, 3, 4));
    assert(transform.try_affine_inverse(&affine_inverse));
    const restored = affine_inverse * (transform * Vector4(1, 2, 3, 1));
    assert(close(restored.x, 1) && close(restored.y, 2) && close(restored.z, 3));
}

@system unittest
{
    Matrix4 camera = Matrix4.identity;
    assert(!try_look_at(Vector3.init, Vector3.init, Vector3(0, 1, 0), &camera));
    assert(camera == Matrix4.identity);
    assert(!try_look_at(
        Vector3.init,
        Vector3(0, 0, -1),
        Vector3(0, 0, -2),
        &camera,
    ));
    assert(camera == Matrix4.identity);
    assert(try_look_at(
        Vector3(0, 0, 3),
        Vector3.init,
        Vector3(0, 1, 0),
        &camera,
    ));
    assert(camera.is_finite);
}

unittest
{
    const yaw = radians(35.0f);
    const pitch = radians(-20.0f);
    const expected_direction = direction_from_yaw_pitch(yaw, pitch);
    const rotated_direction = (
        rotation_yaw_pitch_roll(yaw, pitch, 0)
            * Vector4(0, 0, -1, 0)
    ).xyz;
    assert(close(rotated_direction.with_w(0), expected_direction.with_w(0)));

    const base = scaling(2);
    const pre_translated = base.pre_translated(Vector3(1, 0, 0));
    const post_translated = base.post_translated(Vector3(1, 0, 0));
    assert(pre_translated * Vector4(0, 0, 0, 1) == Vector4(1, 0, 0, 1));
    assert(post_translated * Vector4(0, 0, 0, 1) == Vector4(2, 0, 0, 1));
}

unittest
{
    const orientation = Quaternion.from_yaw_pitch_roll(
        radians(35.0f),
        radians(-20.0f),
        radians(15.0f),
    );
    const vector = Vector3(2, -3, 4);
    const matrix3 = Matrix3.from_quaternion(orientation);
    const matrix4 = Matrix4.from_quaternion(orientation);

    assert(close((matrix3 * vector).with_w(0), orientation.rotated(vector).with_w(0)));
    assert(close(
        matrix4.transform_direction(vector).with_w(0),
        orientation.rotated(vector).with_w(0),
    ));
    assert(close(
        Matrix4.from_quaternion(-orientation),
        matrix4,
    ));
    assert(close(
        rotation_yaw_pitch_roll(radians(35.0f), radians(-20.0f), radians(15.0f)),
        matrix4,
    ));
}

unittest
{
    const transform = trs(
        Vector3(2, 3, 4),
        Quaternion.from_axis_angle(Vector3(0, 0, 1), pi / 2),
        Vector3(2, 3, 4),
    );

    assert(close(transform.transform_point(Vector3(1, 0, 0)).with_w(1), Vector4(2, 5, 4, 1)));
    assert(close(transform.transform_direction(Vector3(1, 0, 0)).with_w(0), Vector4(0, 2, 0, 0)));
}

@system unittest
{
    Matrix3 normal_matrix = Matrix3.identity;
    assert(scaling(Vector3(2, 4, 5)).try_normal_matrix(&normal_matrix));
    assert(close((normal_matrix * Vector3(1, 0, 0)).with_w(0), Vector4(0.5f, 0, 0, 0)));
    assert(close((normal_matrix * Vector3(0, 1, 0)).with_w(0), Vector4(0, 0.25f, 0, 0)));
    assert(close((normal_matrix * Vector3(0, 0, 1)).with_w(0), Vector4(0, 0, 0.2f, 0)));

    const singular = scaling(Vector3(1, 0, 1));
    const unchanged = normal_matrix;
    assert(!singular.try_normal_matrix(&normal_matrix));
    assert(normal_matrix == unchanged);
}

@system unittest
{
    const identity = Matrix4.identity;
    Random random = Random.seeded(0xCAFE, 7);
    foreach (_; 0 .. 64)
    {
        const offset = Vector3(
            random.between(-10.0f, 10.0f),
            random.between(-10.0f, 10.0f),
            random.between(-10.0f, 10.0f),
        );
        const factors = Vector3(
            random.between(0.5f, 3.0f),
            random.between(0.5f, 3.0f),
            random.between(0.5f, 3.0f),
        );
        auto axis = Vector3(
            random.between(-1.0f, 1.0f),
            random.between(-1.0f, 1.0f),
            random.between(-1.0f, 1.0f),
        );
        if (axis == Vector3.init) axis.x = 1;

        const value = translation(offset)
            * rotation(axis, random.between(-pi, pi))
            * scaling(factors);
        Matrix4 value_inverse;
        assert(value.try_inverse(&value_inverse));
        assert(close(value * value_inverse, identity, 0.002f));
        assert(value.try_affine_inverse(&value_inverse));
        assert(close(value * value_inverse, identity, 0.002f));
    }
}
