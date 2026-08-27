# os

`import xtb.os;` exposes the low-level operating-system mechanisms that are
shared by higher-level XTB domains:

- `OsError` and native error translation;
- raw wall-clock, monotonic-clock, and sleep primitives;
- descriptor-backed memory mapping;
- raw pipe endpoints and I/O.

Precise low-level modules may expose additional native capability queries, such
as `xtb.os.terminal.isTerminal`. Implementation-only bridges and platform
backends live under `xtb.os.internal` and are not user-facing APIs.

`os` owns mechanisms rather than domain semantics. Files and paths belong to
`xtb.fs`, process and environment semantics belong to `xtb.process`, timestamps
and elapsed-time semantics belong to `xtb.time`, and ANSI selection policy
belongs to `xtb.terminal`.

The dependency direction is deliberately one-way: `xtb.os` depends only on
`xtb:core`; domain subpackages may depend downward on `xtb.os`, but `xtb.os`
does not import them. Platform selection is compile-time and platform-specific
code is kept behind the public low-level contracts under `xtb.os.internal`.
