# os

`import xtb.os;` exposes the low-level operating-system mechanisms that are
shared by higher-level XTB domains:

- `OsError` and native error translation;
- raw wall-clock, monotonic-clock, and sleep primitives;
- opaque native handles for cross-domain resource exchange;
- handle-backed memory mapping;
- raw pipe endpoints and I/O.

Precise low-level modules may expose additional native capability queries, such
as `xtb.os.terminal.isTerminal` and the C-string lookup in
`xtb.os.environment`. These precise modules are not re-exported from
`import xtb.os;`; callers opt into the native-facing API they need.
Implementation-only bridges and platform backends live under `xtb.os.internal`
and are not user-facing APIs.

`os` owns reusable mechanisms rather than domain semantics. Files and paths
belong to `xtb.fs`, process and environment semantics belong to `xtb.process`,
timestamps and elapsed-time semantics belong to `xtb.time`, and ANSI selection
policy belongs to `xtb.terminal`.

A domain does not need to add a one-off `xtb.os` wrapper merely to hide that its
implementation uses a native API. Domain-specific platform glue stays with the
domain under its own `internal` backend; mechanisms that are useful across
domains belong in `xtb.os`. This keeps both the semantic owner and the native
boundary explicit without turning `os` into a general-purpose services layer.

The dependency direction is deliberately one-way: `xtb.os` depends only on
`xtb:core`; domain subpackages may depend downward on `xtb.os`, but `xtb.os`
does not import them. Platform selection is compile-time, and portable domain
modules keep substantial platform-specific implementations behind internal
backends.
