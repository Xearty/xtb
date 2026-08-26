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
    mkStatic = {pkgs, features ? [], mode ? "release-safe"}: let
      featureArgs = lib.concatStringsSep " " (map lib.escapeShellArg features);
      libbacktrace = staticLibbacktrace pkgs;
    in
      pkgs.stdenv.mkDerivation {
        pname = "xtb-${mode}-${if features == [] then "core" else lib.concatStringsSep "-" features}";
        version = "0.1.0";
        src = projectSource;
        nativeBuildInputs = [pkgs.ldc pkgs.dub];
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [libbacktrace];
        XTB_DIAGNOSTICS_NATIVE_ARCHIVE =
          lib.optionalString pkgs.stdenv.isLinux "${libbacktrace}/lib/libbacktrace.a";
        dontConfigure = true;
        dontStrip = true;
        buildPhase = ''
          runHook preBuild
          export DUB_HOME="$TMPDIR/dub"
          dub run :compose --compiler=ldc2 --skip-registry=all --temp-build -- \
            --mode=${lib.escapeShellArg mode} \
            --output="$out/lib" \
            ${featureArgs}
          runHook postBuild
        '';
        installPhase = "true";
      };
  in {
    lib.mkStatic = mkStatic;

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
      source = pkgs.runCommand "xtb-source" {src = projectSource;} ''
        mkdir -p "$out/include/xtb"
        cp -R "$src/source/core/xtb/." "$out/include/xtb/"
        for feature in "$src"/source/*; do
          if [ "$feature" = "$src/source/core" ] || [ ! -d "$feature/xtb" ]; then
            continue
          fi
          cp -R "$feature/xtb/." "$out/include/xtb/"
        done
      '';
      xtb = pkgs.stdenv.mkDerivation {
        pname = "xtb";
        version = "0.1.0";
        src = projectSource;
        nativeBuildInputs = [pkgs.ldc pkgs.dub pkgs.just];
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [libbacktrace];
        XTB_DIAGNOSTICS_NATIVE_ARCHIVE =
          lib.optionalString pkgs.stdenv.isLinux "${libbacktrace}/lib/libbacktrace.a";
        dontConfigure = true;
        dontStrip = true;
        buildPhase = ''
          runHook preBuild
          export DUB_HOME="$TMPDIR/dub"
          for mode in debug release-safe release-fast; do
            just build static xtb "$mode"
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
          cp -R source/core/xtb $out/include/
          for feature in source/*; do
            if [ "$feature" = source/core ] || [ ! -d "$feature/xtb" ]; then
              continue
            fi
            cp -R "$feature/xtb/." $out/include/xtb/
          done
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
        XTB_DIAGNOSTICS_NATIVE_ARCHIVE =
          lib.optionalString pkgs.stdenv.isLinux "${libbacktrace}/lib/libbacktrace.a";
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
          export XTB_DIAGNOSTICS_NATIVE_ARCHIVE=${lib.optionalString pkgs.stdenv.isLinux "${libbacktrace}/lib/libbacktrace.a"}
          echo "xtb BetterC shell: $(ldc2 --version | head -n 1)"
        '';
      };
    });
  };
}
