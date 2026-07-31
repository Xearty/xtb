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
          ldc2 -betterC -boundscheck=on -wi -de -oq -I=source \
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
        nativeBuildInputs = [pkgs.ldc pkgs.clang];
        buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.libbacktrace];
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          ldc2 -betterC -unittest -boundscheck=on -wi -de -I=source \
            tests/core_tests.d $(find source -name '*.d' -print | sort) \
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-L${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0"} \
            -of=core-tests
          ./core-tests
          ldc2 -betterC -unittest -boundscheck=on -wi -de -I=source \
            tests/math_tests.d source/xtb/math/random.d \
            $(find source -name '*.d' ! -path 'source/xtb/math/random.d' -print | sort) \
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-L${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0"} \
            -of=math-tests
          ./math-tests
          ldc2 -betterC -unittest -boundscheck=on -wi -de -I=source \
            tests/os_tests.d source/xtb/os/path.d \
            $(find source -name '*.d' ! -path 'source/xtb/os/path.d' -print | sort) \
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-L${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0"} \
            -of=os-tests
          ./os-tests
          ldc2 -betterC -unittest -O3 -boundscheck=on -wi -de -I=source \
            tests/core_tests.d $(find source -name '*.d' -print | sort) \
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-L${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0"} \
            -of=core-tests-optimized
          ./core-tests-optimized
          ldc2 -betterC -unittest -O3 -boundscheck=on -wi -de -I=source \
            tests/math_tests.d source/xtb/math/random.d \
            $(find source -name '*.d' ! -path 'source/xtb/math/random.d' -print | sort) \
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-L${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0"} \
            -of=math-tests-optimized
          ./math-tests-optimized
          ldc2 -betterC -unittest -O3 -boundscheck=on -wi -de -I=source \
            tests/os_tests.d source/xtb/os/path.d \
            $(find source -name '*.d' ! -path 'source/xtb/os/path.d' -print | sort) \
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-L${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0"} \
            -of=os-tests-optimized
          ./os-tests-optimized
          clang -std=c11 -Wall -Wextra -Werror \
            -c tests/abi_allocator.c -o abi-allocator-c.o
          ldc2 -betterC -boundscheck=on -wi -de -I=source \
            $(find source -name '*.d' -print | sort) \
            tests/abi_allocator.d abi-allocator-c.o \
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-L${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0"} \
            -of=abi-allocator
          ./abi-allocator
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
      linkedBacktrace =
        if pkgs.stdenv.isLinux
        then
          pkgs.runCommand "libbacktrace-linked" {} ''
            mkdir -p $out/lib
            ln -s ${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0 $out/lib/libbacktrace.so
          ''
        else pkgs.libbacktrace;
    in {
      default = pkgs.mkShell {
        name = "xtbd";
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
          linkedBacktrace
        ];

        shellHook = ''
          export XTB_LIBBACKTRACE=${pkgs.libbacktrace}/lib/libbacktrace.so.0.0.0
          export LIBRARY_PATH=${linkedBacktrace}/lib''${LIBRARY_PATH:+:}$LIBRARY_PATH
          export LD_LIBRARY_PATH=${pkgs.libbacktrace}/lib''${LD_LIBRARY_PATH:+:}$LD_LIBRARY_PATH
          echo "xtbd BetterC shell: $(ldc2 --version | head -n 1)"
        '';
      };
    });
  };
}
