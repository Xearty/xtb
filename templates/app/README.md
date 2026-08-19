# xtb application

This is a BetterC application using XTB through Nix. The flake pins the XTB
revision and exposes its modules and mode-specific static libraries without
copying the library source into this project.

To rename the application, change `appName` in `flake.nix`, then give `name`
and `targetName` in `dub.sdl` the same value. DUB package names must be
lowercase; letters, digits, hyphens, and underscores are the most portable
choice.

## Develop

Enter the development shell and run the application:

```sh
direnv allow
just run
```

Without direnv:

```sh
nix develop path:.
just run
```

The common project commands are:

```sh
just targets
just build                         # debug application and debug XTB
just build release-safe
just build release-fast
just run release-safe
just run release-fast
just run -- argument               # arguments require the explicit separator
just test                          # BetterC unittests outside source/app.d
just test release-safe
just test release-fast
just check                         # format, lint, builds, and tests
just format
just clean
```

`source/greeting.d` demonstrates a module with a colocated unittest. DUB
generates a BetterC test runner and excludes the executable's `source/app.d`
main module. Put ordinary testable logic in non-main modules; use a separate
test package only for integration runners or fixtures that need their own
entry point.

Every application mode links the matching XTB static library. `debug` and
`release-safe` retain bounds checks and `XTB_Checked`; `release-fast` disables
both consistently in the application and library. `debug` additionally keeps
debug information and ordinary application assertions. Release-fast unittests
remain a compile check because that mode removes their assertions.

## Build with Nix

Build or run the default release-safe package:

```sh
nix build path:.
nix run path:.
nix build path:.#debug
nix run path:.#release-fast
nix flake check path:.
```

The named packages and applications are `debug`, `release-safe`, and
`release-fast`; the unqualified default is `release-safe`.

`nix flake check` builds and tests the `debug`, `release-safe`, and
`release-fast` packages. Formatting and linting remain part of `just check`.
The flake also provides `nix fmt` for `flake.nix`.

Update the pinned XTB revision with:

```sh
nix flake update xtb
```

During XTB development, use a local checkout without editing `flake.nix`:

```sh
nix develop path:. --override-input xtb path:/path/to/xtb
nix flake check path:. --override-input xtb path:/path/to/xtb
```

## Linkage

The application links the installed `libxtb.a` from the directory matching its
build mode. Each archive contains one object per module, so the linker selects
only referenced modules while imports from `xtb.core`, `xtb.cli`,
`xtb.diagnostics`, `xtb.math`, `xtb.os`, `xtb.parser`, `xtb.serde`, and
`xtb.threading` remain available without editing library order in `dub.sdl`.
