# xtb application

A BetterC D application template that pins XTB with Nix and builds one
`libxtb.a` from the subpackages the application selects.

## Configure

Set the application name and XTB subpackages in `flake.nix`:

```nix
appName = "my-app";

xtbSubpackages = [
  "log"
  "math"
];
```

Keep `name` and `targetName` in `dub.sdl` equal to `appName`. `core` is always
included, and DUB resolves transitive XTB dependencies automatically.

## Develop

```sh
direnv allow
just run
```

Useful commands:

| Command | Purpose |
|---|---|
| `just targets` | show available targets and modes |
| `just build [mode]` | build the application |
| `just run [mode] -- ...` | run it with optional arguments |
| `just test [mode]` | run BetterC unittests |
| `just check` | format, lint, build, and test |
| `just clean` | remove build outputs |

Modes are `debug`, `release-safe`, and `release-fast`.

Without direnv, enter the shell with `nix develop path:.`.

## Nix

The default Nix package is `release-safe`:

```sh
nix build path:.
nix run path:.
nix build path:.#debug
nix build path:.#release-fast
nix flake check path:.
```

Update the pinned XTB revision with `nix flake update xtb`.
For local XTB development, override the input without editing the flake:

```sh
nix develop path:. --override-input xtb path:/path/to/xtb
```
