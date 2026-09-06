# Allocator interface

`Allocator` is XTB's type-erased allocation callback type. `Allocator*` is the
handle passed to containers and other owning APIs.

```d
import xtb.types;

alias Allocator = extern (C) void* function(
    void* allocator,
    usize new_size,
    void* old_pointer,
    usize old_size,
    usize alignment,
) nothrow @nogc;
```

The arguments tell the callback which operation is being requested:

| Operation | `old_pointer` | `old_size` | `new_size` |
|---|---|---:|---:|
| allocate | `null` | `0` | `> 0` |
| reallocate | existing block | previous size | `> 0` |
| deallocate | existing block | previous size | `0` |

There is no separate operation enum; these values encode the caller's intent.
`alignment` is the alignment of the requested or existing block. Most users only
pass an `Allocator*`; the typed helpers in `xtb.memory` hide this raw callback
interface.

For a stateful custom allocator, put its `Allocator` callback slot first in the
struct and return the address of that slot:

```d
import xtb.memory;
import xtb.types;

struct CountingAllocator
{
    Allocator callback;
    Allocator* backing;
    usize calls;

    static CountingAllocator create(Allocator* backing)
    {
        CountingAllocator result;
        result.callback = &counting_allocator_procedure;
        result.backing = backing;
        return result;
    }

    Allocator* allocator() return
    {
        return &this.callback;
    }
}

static assert(CountingAllocator.callback.offsetof == 0);

private extern (C) void* counting_allocator_procedure(
    void* allocator,
    usize new_size,
    void* old_pointer,
    usize old_size,
    usize alignment,
) nothrow @nogc
{
    auto self = cast(CountingAllocator*) allocator;
    ++self.calls;
    return self.backing.try_reallocate(
        new_size,
        old_pointer,
        old_size,
        alignment,
    );
}
```

XTB passes the address of the callback slot back as `allocator`, so placing the
slot at offset zero lets the callback cast that address back to the allocator
object. The object must therefore stay alive and at a stable address while its
`Allocator*` is in use. `mallocAllocator()` is process-wide and does not have
that lifetime restriction.

Prefer the typed helpers from `xtb.memory` instead of calling the allocator
callback directly:

```d
import xtb.memory;
import xtb.types;

Allocator* allocator = mallocAllocator();

i32* value = allocator.allocate_init!i32();
i32[] values = allocator.allocate_array!i32(32);

allocator.deallocate(value);
allocator.deallocate_array(values);
```

Most allocation operations have a `try_` form that returns `null` on failure and
a non-`try_` form that panics on failure.

| Need | API |
|---|---|
| raw storage | `allocate`, `allocate_array` |
| zeroed POD storage | `allocate_zeroed`, `allocate_zeroed_array` |
| `T.init` lifetime | `allocate_init`, `allocate_init_array` |
| construct with arguments | `create` |
| release raw storage | `deallocate`, `deallocate_array` |
| finalize and release | `dispose`, `dispose_array` |

`deallocate` only releases storage. It does not run `deinit` or a destructor.
Use `dispose` when an allocated value must be finalized first, or use the
owning type's `deinit` API when one exists.

See [Explicit deinit protocol](deinit.md) for cleanup semantics.
