{
  description = "xtb BetterC development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    lib = nixpkgs.lib;
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    forAllSystems = lib.genAttrs supportedSystems;
    staticLibbacktrace = pkgs:
      pkgs.libbacktrace.overrideAttrs (_: {
        dontDisableStatic = true;
        configureFlags = [
          "--enable-static"
          "--disable-shared"
        ];
      });
    projectSource = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.difference ./. (
        lib.fileset.unions [
          ./archive
          (lib.fileset.maybeMissing ./.git)
          (lib.fileset.maybeMissing ./.direnv)
          (lib.fileset.maybeMissing ./.dub)
          (lib.fileset.maybeMissing ./build)
          (lib.fileset.maybeMissing ./result)
        ]
      );
    };
  in {
    templates = {
      default = self.templates.app;

      app = {
        path = ./templates/app;
        description = "A BetterC application using xtb";
      };
    };

    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      libbacktrace = staticLibbacktrace pkgs;
    in rec {
      default = xtb;
      xtb = pkgs.stdenv.mkDerivation {
        pname = "xtb";
        version = "0.1.0";
        src = projectSource;
        nativeBuildInputs = [pkgs.ldc pkgs.dub pkgs.just];
        propagatedBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [libbacktrace];
        dontConfigure = true;
        dontStrip = true;
        buildPhase = ''
          runHook preBuild
          export DUB_HOME="$TMPDIR/dub"
          for mode in debug release-safe release-fast; do
            just build static all "$mode"
          done
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/include
          for mode in debug release-safe release-fast; do
            mkdir -p "$out/lib/$mode"
            cp build/"$mode"/libxtb*.a "$out/lib/$mode/"
          done
          cp -R source/xtb $out/include/
          runHook postInstall
        '';
      };
    });

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      libbacktrace = staticLibbacktrace pkgs;
    in {
      package = self.packages.${system}.xtb;
      tests = pkgs.stdenv.mkDerivation {
        pname = "xtb-tests";
        version = "0.1.0";
        src = projectSource;
        nativeBuildInputs = [
          pkgs.ldc
          pkgs.dub
          pkgs.just
          pkgs.dscanner
          pkgs.dformat
        ];
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [libbacktrace];
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          export DUB_HOME="$TMPDIR/dub"
          just check
          runHook postBuild
        '';
        installPhase = ''
          mkdir -p $out
          touch $out/passed
        '';
      };
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      libbacktrace = staticLibbacktrace pkgs;
    in {
      default = pkgs.mkShell {
        name = "xtb";
        strictDeps = true;

        packages = with pkgs; [
          ldc
          dub
          dscanner
          dformat
          just
          pkg-config
          clang-tools
          lldb
        ];
        buildInputs = lib.optionals pkgs.stdenv.isLinux [libbacktrace];

        shellHook = ''
          export XTB_LIBRARY_OUTPUT_DIR=''${XTB_LIBRARY_OUTPUT_DIR:-"$PWD/build"}
          echo "xtb BetterC shell: $(ldc2 --version | head -n 1)"
        '';
      };
    });
  };
}
