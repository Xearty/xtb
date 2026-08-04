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
    in {
      default = pkgs.stdenv.mkDerivation {
        pname = appName;
        version = "0.1.0";
        src = applicationSource;

        nativeBuildInputs = [pkgs.ldc pkgs.dub];
        buildInputs = [xtbPackage];

        XTB_IMPORT_PATH = "${xtbPackage}/include";
        XTB_LIBRARY_PATH = "${xtbPackage}/lib";

        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          export DUB_HOME="$TMPDIR/dub"
          dub build --compiler=ldc2 --skip-registry=all --build=release
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          install -Dm755 "build/${appName}" "$out/bin/${appName}"
          runHook postInstall
        '';

        meta.mainProgram = appName;
      };
    });

    apps = forAllSystems (system: {
      default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/${appName}";
      };
    });

    checks = forAllSystems (system: {
      package = self.packages.${system}.default;
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

        XTB_IMPORT_PATH = "${xtbPackage}/include";
        XTB_LIBRARY_PATH = "${xtbPackage}/lib";
      };
    });
  };
}
