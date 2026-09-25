# math

`import xtb.math;` provides scalar, vector, quaternion, matrix, transform,
projection, random, and noise utilities. Angle-taking APIs use radians; use
`radians` and `degrees` only when converting at an API boundary. Vectors provide
zero initialization, scalar broadcast (`Vector3(2)`), and composable construction
(`Vector4(position, 1)`). Apart from zero construction and scalar broadcast,
arguments must supply exactly the required number of components. Vectors also
provide `zero`, unit-axis static factories, and compile-time read-only `xyzw`
swizzles of length two through four. Vector arithmetic is component-wise and
accepts scalars on either side of `+`, `-`, `*`, and `/`.

Matrices are column-major: `matrix * vector` transforms a column vector;
`vector * matrix` multiplies a row vector. Matrix `*` is algebraic multiplication;
`hadamard_product` gives component-wise multiplication for matrices or vectors.
Matrices support addition, subtraction, negation, scalar multiplication on either
side, and scalar division. Vectors, matrices, and quaternions support compound
assignment for their corresponding arithmetic operations.

`Quaternion.init` is the identity
rotation, and axis-angle rotations are constructed with `Quaternion.from_axis_angle`.
`trs` composes
translation, rotation, and scale as T * R * S, so scale acts first when transforming
a column vector. `Matrix4.decompose_trs` recovers translation, rotation, and diagonal
scale when the matrix is known to be compatible; `try_decompose_trs` reports singular
or sheared transforms.

Coordinate-independent operations remain generic. Convention-sensitive code can use
`CoordinateSystem` presets with explicit operations such as
`quaternion_from_yaw_pitch_roll(coordinates, ...)`, `look_at_rh`, and `look_at_lh`.
Core APIs never select an implicit coordinate convention.

Applications can provide convention-aware defaults through their own facade module:

```d
module app.math;

public import xtb.math;
import xtb.math.configured;

mixin ConfiguredMath!rh_z_up_y_forward;
```

Application code imports that facade for convention-aware
`direction_from_yaw_pitch`, `quaternion_from_yaw_pitch_roll`,
`rotation_matrix_from_yaw_pitch_roll`, and `look_at` helpers.
The facade already re-exports the rest of `xtb.math`, so consumers import only
`app.math`. Configured and explicit variants form overload sets distinguished by
the explicit variant's leading `CoordinateSystem` argument.
The facade contains compile-time-selected wrappers only; the linked XTB library does not
depend on application configuration.

```d
import app.math;

auto rotation = quaternion_from_yaw_pitch_roll(yaw, pitch, roll);
auto view = look_at(eye, target, up);
auto movement = get_world_forward() + get_world_right();
```

Most operations are allocation-free; `ValueNoise1D` owns allocator-backed
lattice storage. `Random.between` uses half-open `[lower, upper)` ranges for its
integer overloads, and `Random.chance` accepts probabilities in `[0, 1]`.

See [`math_demo.d`](../../examples/math_demo.d).
