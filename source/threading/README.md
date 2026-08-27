# threading

The threading subpackage has two public entry points:

- `xtb.thread` — threads, `spawn`, `JoinHandle`, and `threadScope`.
- `xtb.sync` — atomics, mutexes, condition variables, semaphores, once cells,
  latches, wait groups, barriers, read/write locks, and guards.

The namespaces are separate API domains but intentionally ship together as the
`xtb:threading` component. Thread creation and synchronization share low-level
implementation machinery, so they are not separate composition boundaries.

See the [threading guide](docs/guide.md) for thread ownership and the
[synchronization guide](docs/synchronization.md) for `xtb.sync`.
