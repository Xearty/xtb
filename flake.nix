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
    in rec {
      default = xtb;
      xtb = pkgs.stdenv.mkDerivation {
        pname = "xtb";
        version = "0.1.0";
        src = projectSource;
        nativeBuildInputs = [pkgs.ldc pkgs.dub pkgs.just];
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.libbacktrace];
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          export DUB_HOME="$TMPDIR/dub"
          just build static all release-safe
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib $out/include
          cp build/release-safe/libxtb*.a $out/lib/
          cp -R source/xtb $out/include/
          runHook postInstall
        '';
      };
    });

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      linkedBacktrace = pkgs.runCommand "libbacktrace-linked" {} ''
        mkdir -p $out/lib
        ln -s ${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0 $out/lib/libbacktrace.so
      '';
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
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.libbacktrace];
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          export DUB_HOME="$TMPDIR/dub"
          ${pkgs.lib.optionalString pkgs.stdenv.isLinux "export XTB_LIBBACKTRACE=${linkedBacktrace}/lib/libbacktrace.so"}
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
      linkedBacktrace = pkgs.runCommand "libbacktrace-linked" {} ''
        mkdir -p $out/lib
        ln -s ${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0 $out/lib/libbacktrace.so
      '';
    in {
      default = pkgs.mkShell {
        name = "xtb";
        strictDeps = true;

        packages = with pkgs;
          [
            ldc
            dub
            dscanner
            dformat
            just
            pkg-config
            clang-tools
            lldb
          ]
          ++ lib.optionals stdenv.isLinux [linkedBacktrace];

        shellHook = ''
          export XTB_LIBRARY_OUTPUT_DIR=''${XTB_LIBRARY_OUTPUT_DIR:-"$PWD/build"}
          ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
            export XTB_LIBBACKTRACE=${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0
            export LIBRARY_PATH=${linkedBacktrace}/lib''${LIBRARY_PATH:+:}$LIBRARY_PATH
            export LD_LIBRARY_PATH=${pkgs.libbacktrace}/lib''${LD_LIBRARY_PATH:+:}$LD_LIBRARY_PATH
          ''}
          echo "xtb BetterC shell: $(ldc2 --version | head -n 1)"
        '';
      };
    });
  };
}
