# os

`import xtb.os;` exposes low-level operating-system mechanisms and error
translation used by higher-level XTB domains. It includes clock primitives,
native terminal queries, memory-mapping mechanisms, raw environment access for
XTB internals, and raw pipes.

Higher-level filesystem, process, time, and terminal policy live in their
respective subpackages and depend downward on this package.
