module xtb.math.vector;

nothrow @nogc @safe:

import xtb.math.scalar;
import xtb.panic;
import xtb.types;

private bool is_valid_swizzle(String swizzle, String components) pure
{
    if (swizzle.length < 2 || swizzle.length > 4) return false;

    bool position_family = true;
    bool color_family = true;

    foreach (component; swizzle)
    {
        bool position_found = false;
        bool color_found = false;

        foreach (index, available; components)
        {
            position_found |= component == available;
            color_found |= component == "rgba"[index];
        }

        position_family &= position_found;
        color_family &= color_found;
    }

    return position_family || color_family;
}

private template SwizzleValue(usize count)
{
    static if (count == 2)
    {
        alias SwizzleValue = Vector2;
    }
    else static if (count == 3)
    {
        alias SwizzleValue = Vector3;
    }
    else static if (count == 4)
    {
        alias SwizzleValue = Vector4;
    }
}

private mixin template VectorComponents(String components)
{
    enum usize component_count = components.length;

    alias r = x;
    alias g = y;

    static if (components.length >= 3)
    {
        alias b = z;
    }

    static if (components.length == 4)
    {
        alias a = w;
    }

    /// Borrows a component in `xyzw` order. `index` must be less than `component_count`.
    // Instantiate in the caller so unchecked contracts also disappear across modules.
    pragma(inline, true)
    ref inout(f32) opIndex()(usize index) inout return
    {
        require(index < components.length, "vector component index is out of bounds");

        // CTFE cannot reinterpret named fields through the overlapping array.
        if (__ctfe)
        {
            static foreach (position; 0 .. components.length)
            {
                if (index == position)
                    return __traits(getMember, this, components[position .. position + 1]);
            }

            panic("vector component index is out of bounds");
        }

        return this.elements[index];
    }

    /// Compares components numerically, including ordinary floating-point NaN semantics.
    pragma(inline, true)
    bool opEquals(typeof(this) other) const pure
    {
        // Compare only named fields, not the duplicate union view (including in CTFE).
        static foreach (position; 0 .. components.length)
        {
            if (__traits(getMember, this, components[position .. position + 1])
                != __traits(getMember, other, components[position .. position + 1]))
            {
                return false;
            }
        }

        return true;
    }

    /// Returns an independent vector value. Swizzles are getter-only and use only `xyzw` or `rgba`.
    @property auto opDispatch(String swizzle)() const pure
    if (is_valid_swizzle(swizzle, components))
    {
        SwizzleValue!(swizzle.length) result;

        static foreach (index; 0 .. swizzle.length)
        {
            __traits(getMember, result, "xyzw"[index .. index + 1]) =
                __traits(getMember, this, swizzle[index .. index + 1]);
        }

        return result;
    }
}

struct Vector2
{
    nothrow @nogc @safe:

    union
    {
        struct
        {
            f32 x = 0;
            f32 y = 0;
        }

        /// Runtime array view of the named fields; use `vector[index]` for CTFE support.
        f32[2] elements;
    }

    mixin VectorComponents!"xy";

    /// Broadcasts `value` to every component.
    this(f32 value) pure
    {
        this(value, value);
    }

    this(f32 x, f32 y) pure
    {
        this.x = x;
        this.y = y;
    }

    this(Vector2 value) pure
    {
        this(value.x, value.y);
    }

    static Vector2 zero() pure
    {
        return Vector2.init;
    }

    static Vector2 unit_x() pure
    {
        return Vector2(1.0f, 0.0f);
    }

    static Vector2 unit_y() pure
    {
        return Vector2(0.0f, 1.0f);
    }

    Vector2 opUnary(string op : "-")() const pure
    {
        return Vector2(-this.x, -this.y);
    }

    Vector2 opBinary(string op : "+")(Vector2 b) const pure
    {
        return Vector2(this.x + b.x, this.y + b.y);
    }

    Vector2 opBinary(string op : "-")(Vector2 b) const pure
    {
        return Vector2(this.x - b.x, this.y - b.y);
    }

    Vector2 opBinary(string op : "*")(Vector2 b) const pure
    {
        return Vector2(this.x * b.x, this.y * b.y);
    }

    Vector2 opBinary(string op : "/")(Vector2 b) const pure
    {
        return Vector2(this.x / b.x, this.y / b.y);
    }

    Vector2 opBinary(string op : "*")(f32 scalar) const pure
    {
        return Vector2(this.x * scalar, this.y * scalar);
    }

    Vector2 opBinary(string op : "/")(f32 scalar) const pure
    {
        return Vector2(this.x / scalar, this.y / scalar);
    }

    Vector2 opBinary(string op : "+")(f32 scalar) const pure
    {
        return Vector2(this.x + scalar, this.y + scalar);
    }

    Vector2 opBinary(string op : "-")(f32 scalar) const pure
    {
        return Vector2(this.x - scalar, this.y - scalar);
    }

    Vector2 opBinaryRight(string op)(f32 scalar) const pure
    if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        return Vector2(scalar).opBinary!op(this);
    }

    ref Vector2 opOpAssign(string op)(Vector2 other) return pure
    if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        this = this.opBinary!op(other);
        return this;
    }

    ref Vector2 opOpAssign(string op)(f32 scalar) return pure
    if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        this = this.opBinary!op(scalar);
        return this;
    }

    Vector3 with_z(f32 z) const pure
    {
        return Vector3(this.x, this.y, z);
    }

    f32 length_squared() const pure
    {
        return this.x * this.x + this.y * this.y;
    }

    bool is_finite() const pure
    {
        return xtb.math.scalar.is_finite(this.x) && xtb.math.scalar.is_finite(this.y);
    }

    f32 length() const
    {
        if (this.x != this.x || this.y != this.y) return f32.nan;

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const scale = xtb.math.scalar.max(absolute_x, absolute_y);
        if (scale == 0) return 0;
        if (scale == f32.infinity) return f32.infinity;

        const scaled_x = absolute_x / scale;
        const scaled_y = absolute_y / scale;
        return scale * sqrt(scaled_x * scaled_x + scaled_y * scaled_y);
    }

    Vector2 normalized() const
    {
        if (!this.is_finite) return Vector2(f32.nan, f32.nan);

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const scale = xtb.math.scalar.max(absolute_x, absolute_y);
        if (scale == 0) return Vector2.init;

        const scaled = this / scale;
        return scaled / sqrt(dot(scaled, scaled));
    }

    f32 projection_length(Vector2 onto) const
    {
        const unit = onto.normalized;
        return unit == Vector2.init ? 0 : dot(this, unit);
    }

    Vector2 projected_onto(Vector2 onto) const
    {
        const unit = onto.normalized;
        return unit == Vector2.init ? Vector2.init : unit * dot(this, unit);
    }

    Vector2 rejected_from(Vector2 onto) const
    {
        return this - this.projected_onto(onto);
    }

    Vector2 reflected(Vector2 unit_normal) const pure
    {
        return this - unit_normal * (2 * dot(this, unit_normal));
    }

    /// Returns this vector rotated counterclockwise by `angle` radians.
    Vector2 rotated(f32 angle) const pure
    {
        const cosine = cos(angle);
        const sine = sin(angle);
        return Vector2(
            this.x * cosine - this.y * sine,
            this.x * sine + this.y * cosine,
        );
    }
}

struct Vector3
{
    nothrow @nogc @safe:

    union
    {
        struct
        {
            f32 x = 0;
            f32 y = 0;
            f32 z = 0;
        }

        /// Runtime array view of the named fields; use `vector[index]` for CTFE support.
        f32[3] elements;
    }

    mixin VectorComponents!"xyz";

    /// Broadcasts `value` to every component.
    this(f32 value) pure
    {
        this(value, value, value);
    }

    this(f32 x, f32 y, f32 z) pure
    {
        this.x = x;
        this.y = y;
        this.z = z;
    }

    this(Vector3 value) pure
    {
        this(value.x, value.y, value.z);
    }

    this(Vector2 xy, f32 z) pure
    {
        this(xy.x, xy.y, z);
    }

    this(f32 x, Vector2 yz) pure
    {
        this(x, yz.x, yz.y);
    }

    static Vector3 zero() pure
    {
        return Vector3.init;
    }

    static Vector3 unit_x() pure
    {
        return Vector3(1.0f, 0.0f, 0.0f);
    }

    static Vector3 unit_y() pure
    {
        return Vector3(0.0f, 1.0f, 0.0f);
    }

    static Vector3 unit_z() pure
    {
        return Vector3(0.0f, 0.0f, 1.0f);
    }

    Vector3 opUnary(string op : "-")() const pure
    {
        return Vector3(-this.x, -this.y, -this.z);
    }

    Vector3 opBinary(string op : "+")(Vector3 b) const pure
    {
        return Vector3(this.x + b.x, this.y + b.y, this.z + b.z);
    }

    Vector3 opBinary(string op : "-")(Vector3 b) const pure
    {
        return Vector3(this.x - b.x, this.y - b.y, this.z - b.z);
    }

    Vector3 opBinary(string op : "*")(Vector3 b) const pure
    {
        return Vector3(this.x * b.x, this.y * b.y, this.z * b.z);
    }

    Vector3 opBinary(string op : "/")(Vector3 b) const pure
    {
        return Vector3(this.x / b.x, this.y / b.y, this.z / b.z);
    }

    Vector3 opBinary(string op : "*")(f32 scalar) const pure
    {
        return Vector3(this.x * scalar, this.y * scalar, this.z * scalar);
    }

    Vector3 opBinary(string op : "/")(f32 scalar) const pure
    {
        return Vector3(this.x / scalar, this.y / scalar, this.z / scalar);
    }

    Vector3 opBinary(string op : "+")(f32 scalar) const pure
    {
        return Vector3(this.x + scalar, this.y + scalar, this.z + scalar);
    }

    Vector3 opBinary(string op : "-")(f32 scalar) const pure
    {
        return Vector3(this.x - scalar, this.y - scalar, this.z - scalar);
    }

    Vector3 opBinaryRight(string op)(f32 scalar) const pure
    if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        return Vector3(scalar).opBinary!op(this);
    }

    ref Vector3 opOpAssign(string op)(Vector3 other) return pure
    if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        this = this.opBinary!op(other);
        return this;
    }

    ref Vector3 opOpAssign(string op)(f32 scalar) return pure
    if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        this = this.opBinary!op(scalar);
        return this;
    }

    Vector4 with_w(f32 w) const pure
    {
        return Vector4(this.x, this.y, this.z, w);
    }

    f32 length_squared() const pure
    {
        return this.x * this.x + this.y * this.y + this.z * this.z;
    }

    bool is_finite() const pure
    {
        return xtb.math.scalar.is_finite(this.x)
            && xtb.math.scalar.is_finite(this.y)
            && xtb.math.scalar.is_finite(this.z);
    }

    f32 length() const
    {
        if (this.x != this.x || this.y != this.y || this.z != this.z) return f32.nan;

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const scale = xtb.math.scalar.max(
            absolute_x,
            xtb.math.scalar.max(absolute_y, absolute_z),
        );
        if (scale == 0) return 0;
        if (scale == f32.infinity) return f32.infinity;

        const scaled_x = absolute_x / scale;
        const scaled_y = absolute_y / scale;
        const scaled_z = absolute_z / scale;
        return scale * sqrt(
            scaled_x * scaled_x + scaled_y * scaled_y + scaled_z * scaled_z,
        );
    }

    Vector3 normalized() const
    {
        if (!this.is_finite) return Vector3(f32.nan, f32.nan, f32.nan);

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const scale = xtb.math.scalar.max(absolute_x, xtb.math.scalar.max(absolute_y, absolute_z));
        if (scale == 0) return Vector3.init;

        const scaled = this / scale;
        return scaled / sqrt(dot(scaled, scaled));
    }

    f32 projection_length(Vector3 onto) const
    {
        const unit = onto.normalized;
        return unit == Vector3.init ? 0 : dot(this, unit);
    }

    Vector3 projected_onto(Vector3 onto) const
    {
        const unit = onto.normalized;
        return unit == Vector3.init ? Vector3.init : unit * dot(this, unit);
    }

    Vector3 rejected_from(Vector3 onto) const
    {
        return this - this.projected_onto(onto);
    }

    Vector3 reflected(Vector3 unit_normal) const pure
    {
        return this - unit_normal * (2 * dot(this, unit_normal));
    }
}

struct Vector4
{
    nothrow @nogc @safe:

    union
    {
        struct
        {
            f32 x = 0;
            f32 y = 0;
            f32 z = 0;
            f32 w = 0;
        }

        /// Runtime array view of the named fields; use `vector[index]` for CTFE support.
        f32[4] elements;
    }

    mixin VectorComponents!"xyzw";

    /// Broadcasts `value` to every component.
    this(f32 value) pure
    {
        this(value, value, value, value);
    }

    this(f32 x, f32 y, f32 z, f32 w) pure
    {
        this.x = x;
        this.y = y;
        this.z = z;
        this.w = w;
    }

    this(Vector4 value) pure
    {
        this(value.x, value.y, value.z, value.w);
    }

    this(Vector3 xyz, f32 w) pure
    {
        this(xyz.x, xyz.y, xyz.z, w);
    }

    this(f32 x, Vector3 yzw) pure
    {
        this(x, yzw.x, yzw.y, yzw.z);
    }

    this(Vector2 xy, Vector2 zw) pure
    {
        this(xy.x, xy.y, zw.x, zw.y);
    }

    this(Vector2 xy, f32 z, f32 w) pure
    {
        this(xy.x, xy.y, z, w);
    }

    this(f32 x, Vector2 yz, f32 w) pure
    {
        this(x, yz.x, yz.y, w);
    }

    this(f32 x, f32 y, Vector2 zw) pure
    {
        this(x, y, zw.x, zw.y);
    }

    static Vector4 zero() pure
    {
        return Vector4.init;
    }

    static Vector4 unit_x() pure
    {
        return Vector4(1.0f, 0.0f, 0.0f, 0.0f);
    }

    static Vector4 unit_y() pure
    {
        return Vector4(0.0f, 1.0f, 0.0f, 0.0f);
    }

    static Vector4 unit_z() pure
    {
        return Vector4(0.0f, 0.0f, 1.0f, 0.0f);
    }

    static Vector4 unit_w() pure
    {
        return Vector4(0.0f, 0.0f, 0.0f, 1.0f);
    }

    Vector4 opUnary(string op : "-")() const pure
    {
        return Vector4(-this.x, -this.y, -this.z, -this.w);
    }

    Vector4 opBinary(string op : "+")(Vector4 b) const pure
    {
        return Vector4(this.x + b.x, this.y + b.y, this.z + b.z, this.w + b.w);
    }

    Vector4 opBinary(string op : "-")(Vector4 b) const pure
    {
        return Vector4(this.x - b.x, this.y - b.y, this.z - b.z, this.w - b.w);
    }

    Vector4 opBinary(string op : "*")(Vector4 b) const pure
    {
        return Vector4(this.x * b.x, this.y * b.y, this.z * b.z, this.w * b.w);
    }

    Vector4 opBinary(string op : "/")(Vector4 b) const pure
    {
        return Vector4(this.x / b.x, this.y / b.y, this.z / b.z, this.w / b.w);
    }

    Vector4 opBinary(string op : "*")(f32 scalar) const pure
    {
        return Vector4(this.x * scalar, this.y * scalar, this.z * scalar, this.w * scalar);
    }

    Vector4 opBinary(string op : "/")(f32 scalar) const pure
    {
        return Vector4(this.x / scalar, this.y / scalar, this.z / scalar, this.w / scalar);
    }

    Vector4 opBinary(string op : "+")(f32 scalar) const pure
    {
        return Vector4(this.x + scalar, this.y + scalar, this.z + scalar, this.w + scalar);
    }

    Vector4 opBinary(string op : "-")(f32 scalar) const pure
    {
        return Vector4(this.x - scalar, this.y - scalar, this.z - scalar, this.w - scalar);
    }

    Vector4 opBinaryRight(string op)(f32 scalar) const pure
    if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        return Vector4(scalar).opBinary!op(this);
    }

    ref Vector4 opOpAssign(string op)(Vector4 other) return pure
    if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        this = this.opBinary!op(other);
        return this;
    }

    ref Vector4 opOpAssign(string op)(f32 scalar) return pure
    if (op == "+" || op == "-" || op == "*" || op == "/")
    {
        this = this.opBinary!op(scalar);
        return this;
    }

    f32 length_squared() const pure
    {
        return this.x * this.x + this.y * this.y + this.z * this.z + this.w * this.w;
    }

    bool is_finite() const pure
    {
        return xtb.math.scalar.is_finite(this.x)
            && xtb.math.scalar.is_finite(this.y)
            && xtb.math.scalar.is_finite(this.z)
            && xtb.math.scalar.is_finite(this.w);
    }

    f32 length() const
    {
        if (this.x != this.x || this.y != this.y || this.z != this.z || this.w != this.w)
            return f32.nan;

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const absolute_w = abs(this.w);
        const scale = xtb.math.scalar.max(
            xtb.math.scalar.max(absolute_x, absolute_y),
            xtb.math.scalar.max(absolute_z, absolute_w),
        );
        if (scale == 0) return 0;
        if (scale == f32.infinity) return f32.infinity;

        const scaled_x = absolute_x / scale;
        const scaled_y = absolute_y / scale;
        const scaled_z = absolute_z / scale;
        const scaled_w = absolute_w / scale;
        return scale * sqrt(
            scaled_x * scaled_x + scaled_y * scaled_y + scaled_z * scaled_z + scaled_w * scaled_w,
        );
    }

    Vector4 normalized() const
    {
        if (!this.is_finite) return Vector4(f32.nan, f32.nan, f32.nan, f32.nan);

        const absolute_x = abs(this.x);
        const absolute_y = abs(this.y);
        const absolute_z = abs(this.z);
        const absolute_w = abs(this.w);
        const scale = xtb.math.scalar.max(
            xtb.math.scalar.max(absolute_x, absolute_y),
            xtb.math.scalar.max(absolute_z, absolute_w),
        );
        if (scale == 0) return Vector4.init;

        const scaled = this / scale;
        return scaled / sqrt(dot(scaled, scaled));
    }
}

/// Returns the component-wise product.
Vector2 hadamard_product(Vector2 a, Vector2 b) pure
{
    return a * b;
}

/// ditto
Vector3 hadamard_product(Vector3 a, Vector3 b) pure
{
    return a * b;
}

/// ditto
Vector4 hadamard_product(Vector4 a, Vector4 b) pure
{
    return a * b;
}

f32 dot(Vector2 a, Vector2 b) pure
{
    return a.x * b.x + a.y * b.y;
}

f32 dot(Vector3 a, Vector3 b) pure
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

f32 dot(Vector4 a, Vector4 b) pure
{
    return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
}

Vector3 cross(Vector3 a, Vector3 b) pure
{
    return Vector3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    );
}

f32 distance_squared(Vector2 a, Vector2 b) pure
{
    return (a - b).length_squared;
}

f32 distance_squared(Vector3 a, Vector3 b) pure
{
    return (a - b).length_squared;
}

f32 distance_squared(Vector4 a, Vector4 b) pure
{
    return (a - b).length_squared;
}

f32 distance(Vector2 a, Vector2 b)
{
    return (a - b).length;
}

f32 distance(Vector3 a, Vector3 b)
{
    return (a - b).length;
}

f32 distance(Vector4 a, Vector4 b)
{
    return (a - b).length;
}

f32 angle(Vector2 a, Vector2 b)
{
    const unit_a = a.normalized;
    const unit_b = b.normalized;
    return unit_a == Vector2.init || unit_b == Vector2.init
        ? 0
        : acos(xtb.math.scalar.clamp(dot(unit_a, unit_b), -1, 1));
}

f32 angle(Vector3 a, Vector3 b)
{
    const unit_a = a.normalized;
    const unit_b = b.normalized;
    return unit_a == Vector3.init || unit_b == Vector3.init
        ? 0
        : acos(xtb.math.scalar.clamp(dot(unit_a, unit_b), -1, 1));
}

/// Returns the signed counterclockwise angle from `from` to `to`, in radians.
f32 signed_angle(Vector2 from, Vector2 to)
{
    const unit_from = from.normalized;
    const unit_to = to.normalized;
    if (unit_from == Vector2.init || unit_to == Vector2.init) return 0;

    const sine = unit_from.x * unit_to.y - unit_from.y * unit_to.x;
    const cosine = xtb.math.scalar.clamp(dot(unit_from, unit_to), -1, 1);
    return atan2(sine, cosine);
}

/// Returns the signed angle from `from` to `to` around `axis`, in radians.
///
/// The input vectors are projected onto the plane perpendicular to `axis`.
f32 signed_angle(Vector3 from, Vector3 to, Vector3 axis)
{
    const unit_axis = axis.normalized;
    if (unit_axis == Vector3.init) return 0;

    const unit_from = from.rejected_from(unit_axis).normalized;
    const unit_to = to.rejected_from(unit_axis).normalized;
    if (unit_from == Vector3.init || unit_to == Vector3.init) return 0;

    const sine = dot(unit_axis, cross(unit_from, unit_to));
    const cosine = xtb.math.scalar.clamp(dot(unit_from, unit_to), -1, 1);
    return atan2(sine, cosine);
}

Vector2 lerp(Vector2 a, Vector2 b, f32 t) pure
{
    return Vector2(
        xtb.math.scalar.lerp(a.x, b.x, t),
        xtb.math.scalar.lerp(a.y, b.y, t),
    );
}

Vector3 lerp(Vector3 a, Vector3 b, f32 t) pure
{
    return Vector3(
        xtb.math.scalar.lerp(a.x, b.x, t),
        xtb.math.scalar.lerp(a.y, b.y, t),
        xtb.math.scalar.lerp(a.z, b.z, t),
    );
}

Vector4 lerp(Vector4 a, Vector4 b, f32 t) pure
{
    return Vector4(
        xtb.math.scalar.lerp(a.x, b.x, t),
        xtb.math.scalar.lerp(a.y, b.y, t),
        xtb.math.scalar.lerp(a.z, b.z, t),
        xtb.math.scalar.lerp(a.w, b.w, t),
    );
}

Vector2 min(Vector2 a, Vector2 b) pure
{
    return Vector2(
        xtb.math.scalar.min(a.x, b.x),
        xtb.math.scalar.min(a.y, b.y),
    );
}

Vector3 min(Vector3 a, Vector3 b) pure
{
    return Vector3(
        xtb.math.scalar.min(a.x, b.x),
        xtb.math.scalar.min(a.y, b.y),
        xtb.math.scalar.min(a.z, b.z),
    );
}

Vector4 min(Vector4 a, Vector4 b) pure
{
    return Vector4(
        xtb.math.scalar.min(a.x, b.x),
        xtb.math.scalar.min(a.y, b.y),
        xtb.math.scalar.min(a.z, b.z),
        xtb.math.scalar.min(a.w, b.w),
    );
}

Vector2 max(Vector2 a, Vector2 b) pure
{
    return Vector2(
        xtb.math.scalar.max(a.x, b.x),
        xtb.math.scalar.max(a.y, b.y),
    );
}

Vector3 max(Vector3 a, Vector3 b) pure
{
    return Vector3(
        xtb.math.scalar.max(a.x, b.x),
        xtb.math.scalar.max(a.y, b.y),
        xtb.math.scalar.max(a.z, b.z),
    );
}

Vector4 max(Vector4 a, Vector4 b) pure
{
    return Vector4(
        xtb.math.scalar.max(a.x, b.x),
        xtb.math.scalar.max(a.y, b.y),
        xtb.math.scalar.max(a.z, b.z),
        xtb.math.scalar.max(a.w, b.w),
    );
}

Vector2 clamp(Vector2 v, Vector2 lower, Vector2 upper) pure
{
    return max(lower, min(v, upper));
}

Vector3 clamp(Vector3 v, Vector3 lower, Vector3 upper) pure
{
    return max(lower, min(v, upper));
}

Vector4 clamp(Vector4 v, Vector4 lower, Vector4 upper) pure
{
    return max(lower, min(v, upper));
}

bool approximately_equal(
    Vector2 a,
    Vector2 b,
    f32 absolute_tolerance,
    f32 relative_tolerance,
)
{
    const x_equal = xtb.math.scalar.approximately_equal(
        a.x,
        b.x,
        absolute_tolerance,
        relative_tolerance,
    );
    const y_equal = xtb.math.scalar.approximately_equal(
        a.y,
        b.y,
        absolute_tolerance,
        relative_tolerance,
    );
    return x_equal && y_equal;
}

bool approximately_equal(
    Vector3 a,
    Vector3 b,
    f32 absolute_tolerance,
    f32 relative_tolerance,
)
{
    const x_equal = xtb.math.scalar.approximately_equal(
        a.x,
        b.x,
        absolute_tolerance,
        relative_tolerance,
    );
    const y_equal = xtb.math.scalar.approximately_equal(
        a.y,
        b.y,
        absolute_tolerance,
        relative_tolerance,
    );
    const z_equal = xtb.math.scalar.approximately_equal(
        a.z,
        b.z,
        absolute_tolerance,
        relative_tolerance,
    );
    return x_equal && y_equal && z_equal;
}

bool approximately_equal(
    Vector4 a,
    Vector4 b,
    f32 absolute_tolerance,
    f32 relative_tolerance,
)
{
    const x_equal = xtb.math.scalar.approximately_equal(
        a.x,
        b.x,
        absolute_tolerance,
        relative_tolerance,
    );
    const y_equal = xtb.math.scalar.approximately_equal(
        a.y,
        b.y,
        absolute_tolerance,
        relative_tolerance,
    );
    const z_equal = xtb.math.scalar.approximately_equal(
        a.z,
        b.z,
        absolute_tolerance,
        relative_tolerance,
    );
    const w_equal = xtb.math.scalar.approximately_equal(
        a.w,
        b.w,
        absolute_tolerance,
        relative_tolerance,
    );
    return x_equal && y_equal && z_equal && w_equal;
}

// Named fields and indexed storage must describe exactly the same packed floats.
static assert(Vector2.sizeof == f32[2].sizeof);
static assert(Vector2.alignof == f32[2].alignof);
static assert(Vector2.elements.offsetof == 0);
static assert(Vector2.x.offsetof == 0);
static assert(Vector2.y.offsetof == f32.sizeof);

static assert(Vector3.sizeof == f32[3].sizeof);
static assert(Vector3.alignof == f32[3].alignof);
static assert(Vector3.elements.offsetof == 0);
static assert(Vector3.x.offsetof == 0);
static assert(Vector3.y.offsetof == f32.sizeof);
static assert(Vector3.z.offsetof == 2 * f32.sizeof);

static assert(Vector4.sizeof == f32[4].sizeof);
static assert(Vector4.alignof == f32[4].alignof);
static assert(Vector4.elements.offsetof == 0);
static assert(Vector4.x.offsetof == 0);
static assert(Vector4.y.offsetof == f32.sizeof);
static assert(Vector4.z.offsetof == 2 * f32.sizeof);
static assert(Vector4.w.offsetof == 3 * f32.sizeof);

unittest
{
    static assert(Vector2(2) == Vector2(2, 2));
    static assert(Vector3(2) == Vector3(2, 2, 2));
    static assert(Vector4(2) == Vector4(2, 2, 2, 2));

    assert(Vector2() == Vector2.init);
    assert(Vector3() == Vector3.init);
    assert(Vector4() == Vector4.init);
    assert(Vector2(x: 1, y: 2) == Vector2(1, 2));
    assert(Vector3(z: 3, x: 1, y: 2) == Vector3(1, 2, 3));
    assert(Vector4(w: 4, z: 3, y: 2, x: 1) == Vector4(1, 2, 3, 4));

    const pair = Vector2(1, 2);
    const triple = Vector3(1, 2, 3);
    const quadruple = Vector4(1, 2, 3, 4);
    assert(Vector2(pair) == pair);
    assert(Vector3(triple) == triple);
    assert(Vector4(quadruple) == quadruple);
    assert(Vector3(pair, 3) == triple);
    assert(Vector3(1, Vector2(2, 3)) == triple);
    assert(Vector4(triple, 4) == quadruple);
    assert(Vector4(1, Vector3(2, 3, 4)) == quadruple);
    assert(Vector4(pair, Vector2(3, 4)) == quadruple);
    assert(Vector4(pair, 3, 4) == quadruple);
    assert(Vector4(1, Vector2(2, 3), 4) == quadruple);
    assert(Vector4(1, 2, Vector2(3, 4)) == quadruple);
    assert(Vector4(triple, 0).xyz == triple);

    static assert(!__traits(compiles, Vector2(x: 1)));
    static assert(!__traits(compiles, Vector3(1, 2)));
    static assert(!__traits(compiles, Vector3(x: 1, y: 2)));
    static assert(!__traits(compiles, Vector4(1, 2)));
    static assert(!__traits(compiles, Vector4(1, 2, 3)));
    static assert(!__traits(compiles, Vector3(Vector2(1, 2))));
    static assert(!__traits(compiles, Vector3(Vector4(1, 2, 3, 4))));
    static assert(!__traits(compiles, Vector4(Vector3(1, 2, 3))));
    static assert(!__traits(compiles, Vector4(Vector3(1, 2, 3), Vector2(4, 5))));
    static assert(!__traits(compiles, Vector2.splat(1)));
    static assert(!__traits(compiles, Vector3.splat(1)));
    static assert(!__traits(compiles, Vector4.splat(1)));
}

version (unittest)
{
    private void check_vector_arithmetic(V)() pure
    {
        const a = V(2);
        const b = V(8);
        assert(3 + a == V(5));
        assert(3 - a == V(1));
        assert(3 * a == V(6));
        assert(8 / a == V(4));
        assert(-a == V(-2));
        assert(hadamard_product(a, b) == a * b);

        V value = a;
        value += b;
        assert(value == V(10));
        value -= b;
        assert(value == a);
        value *= b;
        assert(value == V(16));
        value /= b;
        assert(value == a);
        value += 2;
        value -= 1;
        value *= 4;
        value /= 2;
        assert(value == V(6));
        assert((value += a) == b);

        value *= value;
        assert(value == V(64));
        value /= value;
        assert(value == V(1));
    }
}

unittest
{
    check_vector_arithmetic!Vector2();
    check_vector_arithmetic!Vector3();
    check_vector_arithmetic!Vector4();
    assert(12 / Vector3(2, 3, 4) == Vector3(6, 4, 3));
    assert(5 - Vector4(1, 2, 3, 4) == Vector4(4, 3, 2, 1));
    assert(hadamard_product(Vector2(2, 3), Vector2(4, 5)) == Vector2(8, 15));

    static assert(!__traits(compiles, Vector2(1) + Vector3(1)));
    static assert(!__traits(compiles, Vector3(1) * Vector4(1)));
}

unittest
{
    const right = Vector2(1, 0);
    const up = Vector2(0, 1);
    assert(approximately_equal(right.rotated(pi / 2), up, 1e-6f, 1e-6f));
    assert(xtb.math.scalar.approximately_equal(signed_angle(right, up), pi / 2, 1e-6f, 1e-6f));
    assert(xtb.math.scalar.approximately_equal(signed_angle(up, right), -pi / 2, 1e-6f, 1e-6f));
}

unittest
{
    const right = Vector3(1, 0, 0);
    const up = Vector3(0, 1, 0);
    const forward = Vector3(0, 0, -1);
    assert(xtb.math.scalar.approximately_equal(
        signed_angle(forward, right, up),
        -pi / 2,
        1e-6f,
        1e-6f,
    ));
    assert(signed_angle(up, right, up) == 0);
}

unittest
{
    assert(Vector2.zero() == Vector2.init);
    assert(Vector2(3.0f) == Vector2(3.0f, 3.0f));
    assert(Vector2.unit_x() == Vector2(1.0f, 0.0f));
    assert(Vector2.unit_y() == Vector2(0.0f, 1.0f));

    assert(Vector3.zero() == Vector3.init);
    assert(Vector3(3.0f) == Vector3(3.0f, 3.0f, 3.0f));
    assert(Vector3.unit_x() == Vector3(1.0f, 0.0f, 0.0f));
    assert(Vector3.unit_y() == Vector3(0.0f, 1.0f, 0.0f));
    assert(Vector3.unit_z() == Vector3(0.0f, 0.0f, 1.0f));

    assert(Vector4.zero() == Vector4.init);
    assert(Vector4(3.0f) == Vector4(3.0f, 3.0f, 3.0f, 3.0f));
    assert(Vector4.unit_x() == Vector4(1.0f, 0.0f, 0.0f, 0.0f));
    assert(Vector4.unit_y() == Vector4(0.0f, 1.0f, 0.0f, 0.0f));
    assert(Vector4.unit_z() == Vector4(0.0f, 0.0f, 1.0f, 0.0f));
    assert(Vector4.unit_w() == Vector4(0.0f, 0.0f, 0.0f, 1.0f));
}

unittest
{
    const vector2 = Vector2(1.0f, 2.0f);
    assert(vector2.yx == Vector2(2.0f, 1.0f));
    assert(vector2.xyy == Vector3(1.0f, 2.0f, 2.0f));
    assert(vector2.yxxy == Vector4(2.0f, 1.0f, 1.0f, 2.0f));

    const vector3 = Vector3(1.0f, 2.0f, 3.0f);
    assert(vector3.xy == Vector2(1.0f, 2.0f));
    assert(vector3.zyx == Vector3(3.0f, 2.0f, 1.0f));
    assert(vector3.xzyz == Vector4(1.0f, 3.0f, 2.0f, 3.0f));

    const vector4 = Vector4(1.0f, 2.0f, 3.0f, 4.0f);
    assert(vector4.wx == Vector2(4.0f, 1.0f));
    assert(vector4.yzw == Vector3(2.0f, 3.0f, 4.0f));
    assert(vector4.wzyx == Vector4(4.0f, 3.0f, 2.0f, 1.0f));
    assert(vector4.xxxx == Vector4(1.0f, 1.0f, 1.0f, 1.0f));
}

static assert(!__traits(compiles, Vector2.init.xz));
static assert(!__traits(compiles, Vector3.init.xw));
static assert(!__traits(compiles, Vector4.init.xyzwx));
static assert(!__traits(compiles, Vector4.init.xq));

version (unittest)
{
    private bool check_component_access(V)()
    {
        auto value = V(0);

        foreach (index; 0 .. V.component_count)
        {
            value[index] = cast(f32)(index + 1);
            assert(value[index] == index + 1);
            value[index] += 4;
            assert(value[index] == index + 5);
        }

        assert(&value[0] is &value.x);
        assert(&value[1] is &value.y);
        assert(&value.r is &value.x);
        assert(&value.g is &value.y);

        static if (V.component_count >= 3)
        {
            assert(&value[2] is &value.z);
            assert(&value.b is &value.z);
        }

        static if (V.component_count == 4)
        {
            assert(&value[3] is &value.w);
            assert(&value.a is &value.w);
        }

        const snapshot = value;
        immutable frozen = V(3);
        static assert(is(typeof(value[0]) == f32));
        static assert(is(typeof(snapshot[0]) == const(f32)));
        static assert(is(typeof(frozen[0]) == immutable(f32)));

        foreach (index; 0 .. V.component_count)
        {
            assert(snapshot[index] == index + 5);
            assert(frozen[index] == 3);
        }

        static assert(!__traits(compiles, snapshot[0] = 1));
        static assert(!__traits(compiles, frozen[0] = 1));

        static assert(!__traits(compiles, ()
        {
            enum invalid = V.init[V.component_count];
        }));
        static assert(!__traits(compiles, ()
        {
            enum invalid = V.init[usize.max];
        }));

        static assert(!__traits(compiles, () @safe
        {
            V local;
            return &local[0];
        }));

        return true;
    }

    private void check_runtime_component_storage(V)()
    {
        // The extra reflected field is a storage alias, not another component.
        static assert(V.tupleof.length == V.component_count + 1);
        static assert(__traits(identifier, V.tupleof[$ - 1]) == "elements");

        V value;

        foreach (index; 0 .. V.component_count)
        {
            assert(value.elements[index] == 0);
            assert(&value.elements[index] is &value[index]);
            value.elements[index] = cast(f32)(index + 1);
        }

        static foreach (position; 0 .. V.component_count)
        {
            assert(__traits(getMember, value, "xyzw"[position .. position + 1]) == position + 1);
            __traits(getMember, value, "xyzw"[position .. position + 1]) += 5;
            assert(value.elements[position] == position + 6);
        }

        const copy = value;
        assert(copy == value);
        value.elements[0] = -1;
        assert(copy.x == 6);
        assert(value.x == -1);
        assert(copy != value);
    }

    private bool check_component_equality(V)() pure
    {
        assert(V(0.0f) == V(-0.0f));
        assert(V(-0.0f) == V(0.0f));
        assert(V(f32.infinity) == V(f32.infinity));
        assert(V(-f32.infinity) == V(-f32.infinity));
        assert(V(f32.infinity) != V(-f32.infinity));

        static foreach (position; 0 .. V.component_count)
        {{
            auto value = V(1);
            __traits(getMember, value, "xyzw"[position .. position + 1]) = 2;
            assert(value != V(1));
            assert(V(1) != value);

            __traits(getMember, value, "xyzw"[position .. position + 1]) = f32.nan;
            const copy = value;
            assert(value != value);
            assert(value != copy);
            assert(copy != value);
        }}

        return true;
    }
}

unittest
{
    static assert(Vector2.component_count == 2);
    static assert(Vector3.component_count == 3);
    static assert(Vector4.component_count == 4);
    static assert(check_component_access!Vector2());
    static assert(check_component_access!Vector3());
    static assert(check_component_access!Vector4());
    assert(check_component_access!Vector2());
    assert(check_component_access!Vector3());
    assert(check_component_access!Vector4());
}

unittest
{
    check_runtime_component_storage!Vector2();
    check_runtime_component_storage!Vector3();
    check_runtime_component_storage!Vector4();
}

unittest
{
    static assert(check_component_equality!Vector2());
    static assert(check_component_equality!Vector3());
    static assert(check_component_equality!Vector4());
    assert(check_component_equality!Vector2());
    assert(check_component_equality!Vector3());
    assert(check_component_equality!Vector4());
}

unittest
{
    const pair = Vector2(1, 2);
    const triple = Vector3(1, 2, 3);
    immutable quadruple = Vector4(1, 2, 3, 4);
    assert(pair.r == 1 && pair.g == 2);
    assert(pair.gr == Vector2(2, 1));
    assert(pair.rgr == Vector3(1, 2, 1));
    assert(pair.ggrr == Vector4(2, 2, 1, 1));
    assert(triple.rgb == triple);
    assert(triple.b == 3);
    assert(triple.bgr == Vector3(3, 2, 1));
    assert(quadruple.a == 4);
    assert(quadruple.abgr == Vector4(4, 3, 2, 1));
    assert(quadruple.aaaa == Vector4(4));

    static assert(is(typeof(pair.gr) == Vector2));
    static assert(is(typeof(triple.bgr) == Vector3));
    static assert(is(typeof(quadruple.abgr) == Vector4));
    auto copy = quadruple.rgb;
    copy.x = 9;
    assert(quadruple.r == 1);
    assert(copy == Vector3(9, 2, 3));
}

version (unittest)
{
    private bool check_swizzle_values(V)() pure
    {
        auto value = V(1);
        value.y = 2;
        const original = value;
        auto pair = value.yx;
        auto triple = value.xyy;
        auto quadruple = value.grrg;

        static assert(is(typeof(pair) == Vector2));
        static assert(is(typeof(triple) == Vector3));
        static assert(is(typeof(quadruple) == Vector4));
        assert(pair == Vector2(2, 1));
        assert(triple == Vector3(1, 2, 2));
        assert(quadruple == Vector4(2, 1, 1, 2));
        assert(value.xy.yx == pair);

        pair += Vector2(3, 4);
        triple.b = 9;
        quadruple *= 2;
        assert(value == original);

        value.x = 7;
        assert(pair == Vector2(5, 5));
        assert(triple == Vector3(1, 2, 9));
        assert(quadruple == Vector4(4, 2, 2, 4));

        static assert(!__traits(compiles, value.xy = Vector2(1)));
        static assert(!__traits(compiles, value.rg = Vector2(1)));
        static assert(!__traits(compiles, value.xyy = Vector3(1)));
        static assert(!__traits(compiles, value.grrg = Vector4(1)));
        return true;
    }
}

unittest
{
    static assert(check_swizzle_values!Vector2());
    static assert(check_swizzle_values!Vector3());
    static assert(check_swizzle_values!Vector4());
    assert(check_swizzle_values!Vector2());
    assert(check_swizzle_values!Vector3());
    assert(check_swizzle_values!Vector4());
}

unittest
{
    auto pair = Vector2(1, 2);
    pair.r = 3;
    pair.g += 4;
    assert(pair == Vector2(3, 6));

    auto triple = Vector3(1, 2, 3);
    triple.b *= 2;
    assert(triple == Vector3(1, 2, 6));

    auto quadruple = Vector4(1, 2, 3, 4);
    quadruple.a = 9;
    assert(quadruple == Vector4(1, 2, 3, 9));
}

unittest
{
    static assert(!__traits(compiles, Vector2.init.b));
    static assert(!__traits(compiles, Vector3.init.a));
    static assert(!__traits(compiles, Vector2.init.rb));
    static assert(!__traits(compiles, Vector3.init.rgba));
    static assert(!__traits(compiles, Vector4.init.xr));
    static assert(!__traits(compiles, Vector4.init.xg));
    static assert(!__traits(compiles, Vector4.init.st));
    static assert(!__traits(compiles, Vector4.init.rgbaa));
    static assert(!__traits(compiles, Vector2.init.xyz));
    static assert(!__traits(compiles, Vector4.init.s));

    Vector4 value;
    static assert(!__traits(compiles, value.xy = Vector2(1)));
    static assert(!__traits(compiles, value.xyz = Vector3(1)));
    static assert(!__traits(compiles, value.xyzw = Vector4(1)));
    static assert(!__traits(compiles, value.rgba = Vector4(1)));
    static assert(!__traits(compiles, value.xy.yx = Vector2(1)));
    static assert(!__traits(compiles, value.xx = Vector2(1)));
    static assert(!__traits(compiles, value.rr = Vector2(1)));
    static assert(!__traits(compiles, value.xyxy = Vector4(1)));
    static assert(!__traits(compiles, value.xg = Vector2(1)));
    static assert(!__traits(compiles, value.xy = Vector3(1)));
    static assert(!__traits(compiles, value.xyz = Vector2(1)));
    static assert(!__traits(compiles, value.rgb = 1));
    static assert(!__traits(compiles, value.xyzw = Vector3(1)));
    static assert(!__traits(compiles, value.a = Vector2(1)));

    const snapshot = value;
    immutable frozen = Vector4(1);
    static assert(!__traits(compiles, snapshot.xy = Vector2(1)));
    static assert(!__traits(compiles, frozen.rgb = Vector3(1)));
    static assert(!__traits(compiles, snapshot.r = 1));
    static assert(!__traits(compiles, frozen.a = 1));
}

unittest
{
    const a = Vector3(1, 2, 3);
    const b = Vector3(4, 5, 6);
    assert(a + b == Vector3(5, 7, 9));
    assert(dot(a, b) == 32);
    assert(cross(Vector3(1, 0, 0), Vector3(0, 1, 0)) == Vector3(0, 0, 1));
    assert(Vector3.init.normalized == Vector3.init);
    assert(Vector3(3, 0, 0).projected_onto(Vector3(0, 2, 0)) == Vector3.init);

    const huge = f32.max;
    const huge_unit = Vector3(huge, huge, 0).normalized;
    assert(huge_unit.length > 0.9999f && huge_unit.length < 1.0001f);

    const tiny_unit = Vector3(1e-30f, -1e-30f, 0).normalized;
    assert(tiny_unit.length > 0.9999f && tiny_unit.length < 1.0001f);

    const projected = Vector3(4, 3, 2).projected_onto(Vector3(huge, 0, 0));
    assert(projected.x == 4 && projected.y == 0 && projected.z == 0);
}
