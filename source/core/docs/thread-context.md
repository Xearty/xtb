# Thread context and scratch arenas

`ThreadContextScope` installs per-thread scratch storage. By default it creates
**two arenas**, each backed by `mallocAllocator()`. `ScratchScope` selects one,
pushes a checkpoint, and automatically rewinds to it when the scope ends.

```d
ThreadContextScope context = ThreadContextScope.acquire(); // two scratch arenas

ScratchScope scratch = ScratchScope.acquire();
int[] temporary = scratch.allocator.allocateArray!int(256);
```

Request scratch with allocator conflicts when existing arena-backed values must
stay valid:

```d
ScratchScope scratch = ScratchScope.acquire(resultAllocator);
```

The selected arena will not be `resultAllocator`.

## Propagating results through a deep call stack

A useful convention is: **each function writes its result into a supplied
allocator and uses a non-conflicting scratch arena for child results**.

```d
int[] add(int[] input, int amount, Allocator* output)
{
    int[] result = output.allocateArray!int(input.length);
    foreach (i, value; input)
        result[i] = value + amount;
    return result;
}

int[] leaf(Allocator* output)
{
    int[] result = output.allocateArray!int(2);
    result[0] = 1;
    result[1] = 2;
    return result;
}

int[] level3(Allocator* output)
{
    ScratchScope scratch = ScratchScope.acquire(output);
    return add(leaf(scratch.allocator), 10, output);
}

int[] level2(Allocator* output)
{
    ScratchScope scratch = ScratchScope.acquire(output);
    return add(level3(scratch.allocator), 100, output);
}

int[] level1(Allocator* output)
{
    ScratchScope scratch = ScratchScope.acquire(output);
    return add(level2(scratch.allocator), 1000, output);
}

void main()
{
    ThreadContextScope context = ThreadContextScope.acquire();
    Allocator* heap = mallocAllocator();

    int[] result = level1(heap);
    scope(exit) heap.deallocateArray(result);
}
```

With the default two arenas, intermediate results alternate down the stack:

```text
level1 scratch / level2 output -> arena A
level2 scratch / level3 output -> arena B
level3 scratch / leaf output   -> arena A (nested checkpoint)
final result                   -> heap
```

Reusing arena A at `level3` is safe: its nested checkpoint only rewinds
allocations made after that checkpoint. The older level1 scratch allocations
remain valid. On the way back up, each level copies/transforms the child result
into its requested output before its scratch scope rewinds.

This ping-pong pattern works at arbitrary call depth with two arenas as long as
each level has one conflicting output allocator. If a function must protect
values from multiple scratch arenas at once, pass all of them to
`ScratchScope.acquire(conflicts)` and create the thread context with enough
arenas. `ThreadContextScope` supports up to `maxScratchArenas` (8).

Scratch access requires an installed thread context; requesting scratch without
one panics.
