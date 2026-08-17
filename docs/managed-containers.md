# Managed container guide

## Purpose

Managed containers bind an allocator to an unmanaged storage type and provide
explicit ownership cleanup through free `deinit`. Their public API is handwritten so declarations remain visible to the
compiler, language servers, documentation tools, and reviewers. Do not generate
managed methods with string mixins, reflection over `allMembers`, or an adapter
template.

Keep the managed type, its unmanaged storage type, and the implementation of its
operations in the same module. A consumer should be able to open one file and
see the representation, factories, ownership rules, and ordinary member API for
that type. The component `package.d` re-exports the module so ordinary code can
use a short import such as `import xtb.core;`; implementation modules still
import focused dependencies.

## Shape of a managed type

A managed container normally contains only its allocator and unmanaged storage:

```d
struct Example
{
    alias Storage = ExampleUnmanaged;
    alias Released = ReleasedStorage!Storage;

private:
    Allocator* allocator_;
    Storage storage_;

version (XTB_Checked)
{
    invariant
    {
        require(&this !is null, "Example pointer is null");
    }
}

public:
    @disable this(this);
    @disable ref Example opAssign(Example source) return;

    static Example create(Allocator* allocator) @trusted;
    static bool tryWithCapacity(
        Allocator* allocator,
        size_t requested,
        scope Example* output,
    ) @trusted;
    static Example withCapacity(
        Allocator* allocator,
        size_t requested,
    ) @trusted;
    static Example adopt(scope Released* released) @trusted;

    void deinit() @trusted;
    bool empty() const pure @safe;
    size_t length() const pure @safe;
    bool tryReserve(size_t requested) @trusted;
    void reserve(size_t requested) @trusted;

    Allocator* allocator() return pure @safe
    {
        return allocator_;
    }
}
```

Static factory methods belong on the type because they establish invariants and
make construction discoverable. Ordinary receiver-owned operations are also
members. This is intentional: code-d/serve-d can resolve and navigate a real
member directly, while large overloaded UFCS adapter sets are much harder for
language servers to resolve reliably.

The allocator binding is a mutable-only member query. It returns `Allocator*`
because allocators are operational handles rather than const data. Do not add a
const allocator accessor or free-function allocator adapters.

D-required hooks such as `opIndex`, `opApply`, `opEquals`, and range primitives
remain members as usual. Ordinary owners do not add `~this` merely for resource
cleanup; destructors are reserved for genuine lexical `Guard`/`Scope` types. They should delegate to the same unmanaged
storage logic as ordinary methods.

## Member calls through pointers

D permits member lookup through a struct pointer, so a separate forwarding
overload is unnecessary:

```d
Example value = Example.create(allocator);
value.reserve(64);

Example* pointer = &value;
pointer.reserve(128);
```

Do not duplicate every method as both `ref Example` and `Example*` free
functions. That forwarding layer adds declarations, worsens LSP overload
resolution, and does not add functionality.

In checked builds, managed structs use a version-gated invariant to reject a
null receiver before a public member executes:

```d
version (XTB_Checked)
{
    invariant
    {
        require(&this !is null, "Example pointer is null");
    }
}
```

`release-fast` omits `XTB_Checked`, so this contract and its expression are not
present. A null receiver is then a caller contract violation with undefined
consequences. Do not rely on checked-mode diagnostics for memory safety at an
`@trusted` boundary that accepts an explicit raw pointer; validate such pointer
arguments where the boundary itself requires it.

## Lifecycle and allocation rules

A handwritten managed type must provide the complete ownership surface
explicitly:

- `create` validates and stores a non-null allocator handle in checked builds.
- Fallible factories leave their output in the zero state on failure.
- `deinit` releases the resources promised by that container's ownership
  semantics. It need not be idempotent or restore `.init`; callers must treat the
  value as dead until reconstructed.
- Ordinary manual owners disable compiler-generated assignment unless the type
  deliberately implements correct replacement semantics. Use `moveAssign` for a
  live explicit-deinit destination and `moveEmplace` only for fresh/dead storage.
- `resetAndRelease` releases storage while preserving the allocator binding.
- `release` transfers the exact allocator/storage pair and leaves the source in
  its zero state.
- `adopt` consumes a release token and restores the same association.
- Mutating methods inject the bound allocator into unmanaged storage.
- Recoverable allocation failure preserves the original value unless the
  operation explicitly documents otherwise.

The unmanaged storage type remains allocator-explicit. Its operations may be
members because the allocator is still supplied explicitly at each allocation
boundary:

```d
storage.tryReserve(allocator, requested);
storage.clear(allocator);
```

Allocator-free raw handoff between internal unmanaged owners uses a move-only
raw-storage token rather than a borrowed slice. That token still requires the
originating allocator for explicit cleanup, so it cannot silently become a
standalone owner or lose allocator provenance during a cross-type transfer.

`ReleasedStorage` requires its payload to expose the lifecycle hooks needed to
release detached storage. The token itself is an explicit owner: if it is not
adopted or extracted, call free `deinit(released)`; scope exit does not free it.

### Element cleanup policy

Allocator ownership and element ownership are separate promises. A shallow
container (`Array`, `HashMap`, `HashSet`, or the value side of `StringHashMap`)
owns its backing allocation but never finalizes stored values. It may therefore
store an explicit owner for workflows that clean every element separately, but
discarding an entry, clearing the container, or deinitializing it abandons that
value without calling either `deinit` or a D destructor.

An owning container (`OwnedArray`, `OwnedHashMap`, `OwnedHashSet`, or
`OwnedStringHashMap`) finalizes every value that it discards. Its element type
must satisfy `canFinalizeWithoutContext!T`: cleanup-free values qualify,
explicit owners must support `deinit(value)` without an allocator or other
context argument, and destructor-only values must have destruction compatible
with `nothrow @nogc`. `finalize(value)` gives all owning containers the same
dispatch rule: explicit `deinit` wins when present; otherwise a D destructor is
run. A value transferred by `pop`, `take`, or extraction is not finalized.

Reserve, rehash, and storage relocation move live values and are not discard
operations. Removal, replacement, shrinking that drops logical elements,
`clear`, and container `deinit` do finalize owned values. Failed insertion
preserves caller ownership.

## Member versus free-function rule

Use a member when the operation conceptually belongs to one owning receiver:

- `length`, `capacity`, `empty`, `view`
- `append`, `prepend`, `insert`, `assign`
- `reserve`, `resize`, `clear`, `remove`, `shrinkToFit`
- `find`, `contains`, `cursor`, `pointerItems`
- `release`, `deinit`, `clone`

Use a free function when a member is impossible or misleading:

- algorithms on `String`, which is an alias to `const(char)[]` and therefore
  cannot contain members;
- generic algorithms over native slices/ranges;
- operations whose semantics genuinely combine unrelated peer types rather than
  having one clear owning receiver;
- builder helpers whose primary abstraction is an algorithm rather than the
  container itself.

Free algorithms may still be designed for UFCS where that improves readability,
but do not create a free forwarding layer merely to imitate member syntax.

## Checked contracts

Every removable contract import and call remains behind `XTB_Checked`:

```d
version (XTB_Checked)
{
    require(output !is null, "output pointer is null");
    require(output.empty, "output is already initialized");
}
```

When several checks are adjacent, use one scoped version block. Conditions
passed to `require` may only inspect already-computed state. Never put required
computation, mutation, allocation, or output initialization inside a removable
contract expression.

The three supported modes are:

- `debug`: checked contracts, native assertions/contracts, bounds checks, debug
  information;
- `release-safe`: optimized with checked contracts and bounds checks retained;
- `release-fast`: optimized with `XTB_Checked` absent, native release mode, and
  bounds checks disabled.

See `docs/build-modes.md` for the exact build commands.

## Naming and module surface

Use short verbs shared across containers: `length`, `empty`, `reserve`,
`tryReserve`, `append`, `add`, `set`, `find`, `remove`, `clear`, `release`, and
`deinit`. Do not prefix operations with the type name.

Add each public container module to the relevant `package.d`. Do not place
implementation in `package.d`; it is only a stable re-export surface.

## Review checklist

Before adding or changing a managed container, verify:

1. The type, unmanaged storage, and member implementation are visible in one
   file.
2. No generated declarations or reflection-driven forwarding remain.
3. The managed type is non-copyable, unsafe generated assignment is disabled,
   and its zero state is safe to deinitialize.
4. Ordinary receiver-owned operations are real members, not UFCS adapters.
5. The allocator accessor is mutable-only and returns `Allocator*`.
6. Checked-mode null-receiver diagnostics are provided without adding runtime
   work to release-fast.
7. Factories, allocation failure, release/adopt, repeated cleanup, and member
   pointer syntax are covered by tests.
8. The module is re-exported by the component `package.d` and a short-import
   consumer compiles.
