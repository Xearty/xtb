# Allocator interface

`Allocator` is XTB's type-erased allocation callback type. `Allocator*` is the
handle passed to containers and other owning APIs.

```d
alias Allocator = extern (C) void* function(
    void* context,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
);
```

The arguments tell the callback which operation is being requested:

| Operation | `oldPointer` | `oldSize` | `newSize` |
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
import xtb.memory : Allocator, tryReallocate;

struct CountingAllocator
{
    private Allocator allocator_;
    Allocator* backing;
    size_t calls;

    static CountingAllocator create(Allocator* backing)
    {
        CountingAllocator result;
        result.allocator_ = &countingAllocatorProcedure;
        result.backing = backing;
        return result;
    }

    Allocator* allocator() return
    {
        return &allocator_;
    }
}

static assert(CountingAllocator.allocator_.offsetof == 0);

private extern (C) void* countingAllocatorProcedure(
    void* context,
    size_t newSize,
    void* oldPointer,
    size_t oldSize,
    size_t alignment,
)
{
    auto self = cast(CountingAllocator*) context;
    ++self.calls;
    return self.backing.tryReallocate(
        newSize,
        oldPointer,
        oldSize,
        alignment,
    );
}
```

XTB passes the address of the callback slot back as `context`, so placing the
slot at offset zero lets the callback cast that address back to the allocator
object. The object must therefore stay alive and at a stable address while its
`Allocator*` is in use. `mallocAllocator()` is process-wide and does not have
that lifetime restriction.

Prefer the typed helpers from `xtb.memory` instead of calling the allocator
callback directly:

```d
Allocator* allocator = mallocAllocator();

int* value = allocator.allocateInit!int();
int[] values = allocator.allocateArray!int(32);

allocator.deallocate(value);
allocator.deallocateArray(values);
```

Most allocation operations have a `try*` form that returns `null` on failure and
a non-`try` form that panics on failure.

| Need | API |
|---|---|
| raw storage | `allocate`, `allocateArray` |
| zeroed POD storage | `allocateZeroed`, `allocateZeroedArray` |
| `T.init` lifetime | `allocateInit`, `allocateInitArray` |
| construct with arguments | `create` |
| release raw storage | `deallocate`, `deallocateArray` |
| finalize and release | `dispose`, `disposeArray` |

`deallocate` only releases storage. It does not run `deinit` or a destructor.
Use `dispose` when an allocated value must be finalized first, or use the
owning type's `deinit` API when one exists.

See [Explicit deinit protocol](deinit.md) for cleanup semantics.
