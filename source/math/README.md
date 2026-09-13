# math

`import xtb.math;` provides scalar, vector, quaternion, matrix, transform,
projection, random, and noise utilities. Angle-taking APIs use radians; use
`radians` and `degrees` only when converting at an API boundary. Matrices are
column-major and multiply column vectors. `Quaternion.init` is the identity
rotation, and quaternion rotations are constructed through static members such as
`Quaternion.from_axis_angle` and `Quaternion.from_yaw_pitch_roll`. `trs` composes
translation, rotation, and scale as T * R * S, so scale acts first when transforming
a column vector.

Most operations are allocation-free; `ValueNoise1D` owns allocator-backed
lattice storage. `Random.between` uses half-open `[lower, upper)` ranges for its
integer overloads, and `Random.chance` accepts probabilities in `[0, 1]`.

See [`math_demo.d`](../../examples/math_demo.d).
