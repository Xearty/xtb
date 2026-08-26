# Synchronization

`xtb.sync` provides allocation-free synchronization primitives. Once a primitive
can be accessed or waited on by another thread, keep it at a stable address
until that access has finished; do not move or copy a published synchronization
object.

| Primitive | Use |
|---|---|
| `Atomic!T` | atomic scalar state and optional wait/notify |
| `Mutex` / `CondVar` | protected shared state and predicate waiting |
| `Semaphore` | counting permits |
| `Latch` | one-shot countdown |
| `WaitGroup` | dynamic work countdown |
| `Barrier` | reusable fixed-participant phase barrier |
| `Once` / `OnceCell!T` | one-time execution or initialization |
| `RwLock` | shared readers / exclusive writer |
| `SpinWait` | adaptive polling when no wakeup protocol exists |

## Locks and guards

`Mutex.init` is unlocked. Use `LockGuard` for lexical locking when possible:

```d
Mutex mutex;

{
    LockGuard!Mutex guard = LockGuard!Mutex(&mutex);
    updateSharedState();
} // unlocks
```

`RwLock` allows concurrent readers or one writer. It is writer-preferring and
has no recursive, upgrade, or downgrade operation.

```d
{
    ReadLockGuard!RwLock read = ReadLockGuard!RwLock(&lock);
    // shared access
}

{
    WriteLockGuard!RwLock write = WriteLockGuard!RwLock(&lock);
    // exclusive access
}
```

The guard types are move-only lexical owners of a lock acquisition. The lock
must outlive its guard.

## Condition variables

Always wait on a predicate in a loop: `CondVar` permits spurious wakeups.
Concurrent waiters on one condition variable must use the same mutex.

```d
mutex.lock();
while (!ready)
    condition.wait(mutex); // unlocks while waiting, then re-locks
consumeSharedState();
mutex.unlock();
```

The thread changing the predicate protects the shared state with the same
mutex, then calls `notifyOne` or `notifyAll` as appropriate.

## Coordination primitives

```d
Semaphore permits = Semaphore(4);
permits.acquire();
scope(exit) permits.release();

Latch loaded = Latch(workerCount);
// each worker: loaded.countDown();
loaded.wait();

WaitGroup work;
work.add();
// worker: work.done();
work.wait();

Barrier phase = Barrier(workerCount);
// each participant:
phase.arriveAndWait();
```

A `Latch` is one-shot. A `WaitGroup` supports successive generations of dynamic
work; after one generation reaches zero, all existing waiters must return before
a positive `add` starts the next. A `Barrier` is reusable with a fixed initial
participant count; `arriveAndDrop` permanently removes that participant from
later generations.

## Once and OnceCell

`callOnce` runs one module-level or static `nothrow @nogc` initializer exactly
once:

```d
Once once;
callOnce!initializeRuntime(once);
```

`OnceCell!T` combines one-time initialization with storage for the resulting
value:

```d
OnceCell!Config config;
scope(exit) config.deinit();

ref Config value = config.getOrInit!loadConfig();
```

The cell owns the initialized value. Returned references borrow the cell, and
later mutable access is not synchronized automatically. `deinit` explicitly
ends the stored value's lifetime; ordinary scope exit alone does not.

## Atomics and waiting

`Atomic!T` defaults to sequentially consistent operations and also exposes
explicit `MemoryOrder` values. Use acquire/release or weaker ordering only when
the surrounding protocol justifies it.

```d
Atomic!uint state;

// producer
state.store(1, MemoryOrder.release);
static if (Atomic!uint.waitSupported)
    state.notifyAll();

// consumer
static if (Atomic!uint.waitSupported)
    state.wait(0, MemoryOrder.acquire);
assert(state.load(MemoryOrder.acquire) == 1);
```

Notification itself does not publish memory; publish protocol state with an
atomic store or read-modify-write before notifying. `wait` / `notifyOne` /
`notifyAll` are available only when `Atomic!T.waitSupported` is true.

`SpinWait` is for polling when there is no parking/wakeup protocol. It provides
no atomicity or memory ordering of its own, so the condition being polled must
still be read through synchronized state.
