{
  description = "BetterC application using xtb";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    xtb.url = "github:Xearty/xtb";
    xtb.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    xtb,
  }: let
    lib = nixpkgs.lib;
    appName = "xtb-app";
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    forAllSystems = lib.genAttrs supportedSystems;
    applicationSource = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./dub.sdl
        ./source
      ];
    };
  in {
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      xtbPackage = xtb.packages.${system}.default;
      makeApplication = mode: let
        checked = mode != "release-fast";
        buildType =
          if mode == "release-fast"
          then "release-nobounds"
          else mode;
        bounds =
          if mode == "release-fast"
          then "off"
          else "on";
      in
        pkgs.stdenv.mkDerivation {
          pname = appName;
          version = "0.1.0";
          src = applicationSource;

          nativeBuildInputs = [pkgs.ldc pkgs.dub];
          buildInputs = [xtbPackage];

          XTB_IMPORT_PATH = "${xtbPackage}/include";
          XTB_LIBRARY_PATH = "${xtbPackage}/lib/${mode}";

          dontConfigure = true;
          dontStrip = mode == "debug";
          buildPhase = ''
            runHook preBuild
            export DUB_HOME="$TMPDIR/dub"
            DFLAGS="-boundscheck=${bounds}" dub build --compiler=ldc2 --skip-registry=all --build=${buildType} ${lib.optionalString checked "--d-version=XTB_Checked"}
            runHook postBuild
          '';
          doCheck = true;
          checkPhase = ''
            runHook preCheck
            export DUB_HOME="$TMPDIR/dub"
            DFLAGS="-boundscheck=${bounds}" dub test --compiler=ldc2 --skip-registry=all --build=${buildType} ${lib.optionalString checked "--d-version=XTB_Checked"}
            runHook postCheck
          '';
          installPhase = ''
            runHook preInstall
            install -Dm755 "build/${appName}" "$out/bin/${appName}"
            runHook postInstall
          '';

          meta.mainProgram = appName;
        };
    in rec {
      default = release-safe;
      debug = makeApplication "debug";
      release-safe = makeApplication "release-safe";
      release-fast = makeApplication "release-fast";
    });

    apps = forAllSystems (system: let
      makeApp = mode: {
        type = "app";
        program = "${self.packages.${system}.${mode}}/bin/${appName}";
        meta.description = "BetterC application using XTB (${mode})";
      };
    in rec {
      default = release-safe;
      debug = makeApp "debug";
      release-safe = makeApp "release-safe";
      release-fast = makeApp "release-fast";
    });

    checks = forAllSystems (system: {
      inherit (self.packages.${system}) debug release-safe release-fast;
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      xtbPackage = xtb.packages.${system}.default;
    in {
      default = pkgs.mkShell {
        name = appName;
        strictDeps = true;

        packages = [
          pkgs.ldc
          pkgs.dub
          pkgs.dscanner
          pkgs.dformat
          pkgs.just
        ];
        buildInputs = [xtbPackage];

        XTB_IMPORT_PATH = "${xtbPackage}/include";
        XTB_LIBRARY_ROOT = "${xtbPackage}/lib";
      };
    });
  };
}
