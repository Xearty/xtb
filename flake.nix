{
  description = "xtb BetterC development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    projectSource = nixpkgs.lib.fileset.toSource {
      root = ./.;
      fileset = nixpkgs.lib.fileset.unions [
        ./.editorconfig
        ./.gitignore
        ./AGENTS.md
        ./README.md
        ./design_spec
        ./docs
        ./dscanner.ini
        ./dub.sdl
        ./examples
        ./flake.lock
        ./flake.nix
        ./fuzz
        ./justfile
        ./source
        ./tests
      ];
    };
  in {
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      default = xtb;
      xtb = pkgs.stdenv.mkDerivation {
        pname = "xtb";
        version = "0.1.0";
        src = projectSource;
        nativeBuildInputs = [pkgs.ldc pkgs.just];
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.libbacktrace];
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          just build
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib $out/include
          cp build/libxtb_*.a $out/lib/
          cp -R source/xtb $out/include/
          runHook postInstall
        '';
      };
    });

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      package = self.packages.${system}.xtb;
      tests = pkgs.stdenv.mkDerivation {
        pname = "xtb-tests";
        version = "0.1.0";
        src = projectSource;
        nativeBuildInputs = [
          pkgs.ldc
          pkgs.clang
          pkgs.just
          pkgs.dscanner
          pkgs.dformat
        ];
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.libbacktrace];
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          ${pkgs.lib.optionalString pkgs.stdenv.isLinux "export XTB_LIBBACKTRACE=${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0"}
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
