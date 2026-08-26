# core

`core` is XTB's base subpackage. `import xtb;` exposes allocators, containers,
strings and UTF-8 helpers, formatting, `Option`, `Result`, durations, flags,
ANSI helpers, and other low-level utilities.

Useful documentation:

- [Allocator interface](docs/allocator.md)
- [Malloc allocator](docs/malloc-allocator.md)
- [Arena allocator](docs/arena.md)
- [Instrumented allocator](docs/instrumented-allocator.md)
- [Thread context and scratch arenas](docs/thread-context.md)
- [Ownership and lifetimes](docs/ownership.md)
- [Container ownership](docs/containers.md)
- [Strings](docs/strings.md)
- [Option and Result](docs/option-result.md)
- [Explicit deinit protocol](docs/deinit.md)
- [Formatting and writers](docs/formatting.md)
- [Virtual arrays and pools](docs/pools.md)
- [Intrusive collections](docs/intrusive-collections.md)

See the `core`, `string`, `print`, `option`, `result`, `ecs`, and `pool-world`
examples under [`examples/`](../../examples/).
