# Threading guide

`xtb.thread` provides raw and typed thread creation plus higher-level joining:

| API | Use |
|---|---|
| `Thread` | explicit native thread lifecycle |
| `spawn` / `JoinHandle!T` | typed result-producing thread |
| `threadScope` | scoped children that are joined before the scope exits |

Owning thread handles must be joined, detached where supported by that handle,
or otherwise explicitly released according to their API. `JoinHandle` is
join-only.

`xtb.sync` provides:

| Primitive | Purpose |
|---|---|
| `Atomic` / `SpinWait` | atomic operations and bounded spinning |
| `Mutex`, `CondVar` | mutual exclusion and condition waiting |
| `Semaphore` | permit counting |
| `Once`, `OnceCell` | one-time execution/initialization |
| `Latch`, `WaitGroup`, `Barrier` | multi-thread coordination |
| `RwLock` | shared/exclusive locking |
| lock guards | scoped lock release |

Synchronization objects must remain at a stable address while they can be used
or waited on. Do not move or copy a live mutex, condition variable, semaphore,
barrier, or similar primitive.

Use the memory-ordering operations from `xtb.sync.atomic` when sharing state
without a higher-level lock. Thread start/join and synchronization primitives
provide their documented ordering; unrelated non-atomic shared memory still
requires synchronization.

## Component boundary

`xtb.thread` and `xtb.sync` are separate public namespaces inside one
`xtb:threading` subpackage. This is deliberate: thread implementation can use
synchronization primitives, and synchronization implementation can use
current-thread operations, without turning that implementation relationship
into a cycle between separately composable packages.

The native threading backend is platform-specific. Check returned start/spawn
errors rather than assuming thread creation succeeds.
