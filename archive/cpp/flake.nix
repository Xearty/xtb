{
  description = "A Vulkan project with Flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        llvmPkgs = pkgs.llvmPackages_22;
        mkShell = pkgs.mkShell.override { stdenv = llvmPkgs.stdenv; };
      in
      {
        devShells.default = mkShell {
          name = "default";
          nativeBuildInputs = with pkgs; [
            raylib
            pkg-config
            just
            bear
            readline
            libbacktrace
            glfw3
            assimp
            stb
            cmake

            llvmPkgs.clang-tools
          ];
        };
      }
    );
}
