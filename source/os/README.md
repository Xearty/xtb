# os

`xtb.os` is XTB's low-level native-mechanism layer. The broad `import xtb.os;`
contains only mechanisms that have a useful platform-neutral contract:

- `OsError`;
- opaque `NativeHandle` values for cross-domain resource exchange;
- raw pipe endpoints and I/O.

Platform interfaces are first-class low-level APIs rather than hidden backends:

- `xtb.os.posix` exposes thin POSIX mechanisms such as errno translation,
  file-descriptor adapters, environment and terminal queries, memory mapping,
  and clocks;
- `xtb.os.linux` exposes Linux-specific mechanisms such as `pipe2`-based pipe
  creation and I/O.

Higher-level domains own portability and semantics. `xtb.time` selects the
platform clock mechanism, `xtb.fs` owns file-backed mapping lifetime and
filesystem concepts, `xtb.process` owns process/environment semantics, and
`xtb.terminal` owns ANSI-selection policy. Their platform-specific
implementations may call `xtb.os.posix`, `xtb.os.linux`, or future platform
interfaces directly.

`xtb.os.internal` is reserved for implementation details beneath these
low-level APIs, such as unsupported-target shims. It is not the platform API
surface.

The dependency direction remains one-way: `xtb.os` depends only on `xtb:core`;
domain subpackages may depend downward on `xtb.os`, but `xtb.os` does not
import them. A domain does not need a generic `xtb.os` wrapper merely to hide
that its implementation uses a native API.
