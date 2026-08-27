# os

`import xtb.os;` exposes low-level operating-system mechanisms and error
translation used by higher-level XTB domains. It includes environment access,
clock primitives, terminal capability queries, memory-mapping mechanisms, and
raw pipes.

Higher-level filesystem, process, and time semantics live in their respective
subpackages and depend downward on this package.
