# Explicit deinit protocol

A `deinit` method is best thought of as an **explicitly and conditionally called
destructor**. It describes how a live value is torn down, but the language does
not invoke it automatically: user or generic code calls it only when that value
actually needs to be destroyed. This keeps cleanup visible and allows cleanup to
require external context.

Concrete owners normally expose `deinit`, and cleanup should be registered
immediately after acquisition:

```d
OwnedString name = "xtb".copy(heap);
scope (exit) name.deinit();
```

`xtb.lifetime.deinit(value, ...)` is the generic protocol entry point. A public,
non-static `void deinit(...)` member is authoritative and receives any cleanup
arguments supplied to the free function:

```d
struct Buffer
{
    ArrayUnmanaged!u8 bytes;

    void deinit(Allocator* allocator) nothrow @nogc
    {
        this.bytes.deinit(allocator);
    }
}

Buffer buffer;
scope (exit) deinit(buffer, heap);
```

Use a member `deinit` when cleanup needs external context, custom ordering, or
other type-specific behavior. If a destructor-free aggregate has no member
`deinit`, the free function can clean it structurally by deinitializing
cleanup-bearing fields in reverse declaration order.

```d
struct Session
{
    OwnedString name;
    OwnedArray!Request requests;
}

Session session;
scope (exit) deinit(session);
```

Borrowed values, raw pointers, and cleanup-free values do not participate in the
protocol; attempting to `deinit` them is a compile-time error.

## Generic lifetime code

| API | Meaning |
|---|---|
| `needs_deinit!T` | `T` has explicit deinitialization work |
| `needs_finalization!T` | `T` needs explicit cleanup or D destruction |
| `can_finalize_without_context!T` | a generic container can discard `T` without extra arguments |
| `finalize(value)` | perform whichever supported cleanup model `T` uses |

`finalize` is primarily for generic/container code. Ordinary XTB owners should
use their explicit `deinit` contract.

## Moving owners

`move(source)` transfers a live owner and resets the source to a safely
deinitializable state. `move_emplace` transfers into dead/uninitialized storage;
`move_assign` first deinitializes a live destination and then replaces it.

See [Ownership and lifetimes](ownership.md) for the higher-level borrowed,
owned, arena, and container lifetime rules.
