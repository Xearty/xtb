# math

`import xtb.math;` provides scalar, vector, matrix, transform, projection, random,
and noise utilities. Most operations are allocation-free; `ValueNoise1D` owns
allocator-backed lattice storage. Matrices are column-major and multiply column
vectors.

See [`math_demo.d`](../../examples/math_demo.d).
