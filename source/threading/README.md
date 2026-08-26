# threading

The threading subpackage has two public entry points:

- `xtb.thread` — threads, `spawn`, `JoinHandle`, and `threadScope`.
- `xtb.sync` — atomics, mutexes, condition variables, semaphores, once cells,
  latches, wait groups, barriers, read/write locks, and guards.

See the [threading guide](docs/guide.md) for thread ownership and the
[synchronization guide](docs/synchronization.md) for `xtb.sync`.
