{
  description = "xtbd BetterC development environment";

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
  in {
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      default = xtbd;
      xtbd = pkgs.stdenv.mkDerivation {
        pname = "xtbd";
        version = "0.1.0";
        src = self;
        nativeBuildInputs = [pkgs.ldc];
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.libbacktrace];
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          mkdir -p build
          ldc2 -betterC -boundscheck=on -w -de -preview=dip1000 -oq -I=source \
            -lib $(find source -name '*.d' -print | sort) \
            -of=build/libxtbd.a
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib $out/include
          cp build/libxtbd.a $out/lib/
          cp -R source/xtb $out/include/
          runHook postInstall
        '';
      };
    });

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      package = self.packages.${system}.xtbd;
      tests = pkgs.stdenv.mkDerivation {
        pname = "xtbd-tests";
        version = "0.1.0";
        src = self;
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
        name = "xtbd";
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
          echo "xtbd BetterC shell: $(ldc2 --version | head -n 1)"
        '';
      };
    });
  };
}
