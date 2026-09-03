# xtb

XTB is a BetterC-first foundational library for D. It avoids the GC, exceptions,
classes, and runtime reflection, and keeps allocation and ownership explicit.

## Subpackages

| Subpackage | Import | Provides |
|---|---|---|
| [core](source/core/README.md) | `xtb` | allocators, containers, strings, formatting, `Option`, `Result`, utilities |
| [os](source/os/README.md) | `xtb.os`, `xtb.os.posix`, `xtb.os.linux` | low-level native errors, handles, pipes, and platform interfaces |
| [terminal](source/terminal/README.md) | `xtb.terminal` | terminal capability policy and ANSI selection |
| [fs](source/fs/README.md) | `xtb.fs` | paths, files, directories, metadata, file-backed mappings |
| [process](source/process/README.md) | `xtb.process` | process environment, commands, child processes, communication, pipelines |
| [time](source/time/README.md) | `xtb.time` | timestamps, monotonic instants, timeouts, sleeping |
| [window](source/window/README.md) | `xtb.window` | desktop windows, input, OpenGL contexts, native graphics handles |
| [opengl](source/opengl/README.md) | `xtb.opengl` | BetterC OpenGL 4.6 bindings and runtime function loading |
| [log](source/log/README.md) | `xtb.log` | level-based logging and composable sinks |
| [math](source/math/README.md) | `xtb.math` | vectors, matrices, transforms, random, noise |
| [threading](source/threading/README.md) | `xtb.thread`, `xtb.sync` | threads and synchronization primitives |
| [parser](source/parser/README.md) | `xtb.parser` | parser combinators and reusable grammars |
| [serde](source/serde/README.md) | `xtb.serde` | serialization and deserialization |
| [cli](source/cli/README.md) | `xtb.cli` | typed command-line parser |
| [diagnostics](source/diagnostics/README.md) | `xtb.diagnostics` | stack traces, demangling, crash diagnostics |

`core` is the base subpackage. DUB resolves transitive subpackage dependencies.

## Start an application

```sh
nix flake new -t github:Xearty/xtb#app ./my-app
cd my-app
direnv allow
just run
```

See the [application template](templates/app/README.md) for selecting subpackages.

## Build modes

| Mode | Use |
|---|---|
| `debug` | development with checks and debug information |
| `release-safe` | optimized build with checks retained |
| `release-fast` | optimized build with checked-only contracts removed |

```sh
just build
just release-safe
just release-fast
just check
```

See [build modes](docs/build-modes.md) for the exact differences.

Contributors should follow the [XTB style guide](docs/style-guide.md).
