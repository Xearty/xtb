# xtb application

This is a BetterC application using xtb through Nix. The flake pins the xtb
revision, provides the D toolchain, and exposes xtb's installed modules and
static libraries to DUB. It does not clone or copy the xtb source tree.

To rename the application, change `appName` in `flake.nix`, then give `name`
and `targetName` in `dub.sdl` the same value. DUB package names must be
lowercase; letters, digits, hyphens, and underscores are the most portable
choice.

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

Other common commands are:

```sh
just build
just check
just format
nix build path:.
nix run path:.
```

Update the pinned xtb revision with:

```sh
nix flake update xtb
```

During xtb development, use a local checkout without changing `flake.nix`:

```sh
nix develop path:. --override-input xtb path:/path/to/xtb
```

The template links `xtb_core`. Add another installed component to `libs` in
`dub.sdl` when the application imports it. Keep dependencies after their users
for static linking; for example:

```sdl
libs "xtb_diagnostics" "xtb_os" "xtb_core"
```

Linux programs using `xtb_diagnostics` must also link `backtrace`.
