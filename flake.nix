{
  description = "A Vulkan project with Flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          name = "default";
          nativeBuildInputs = with pkgs; [
            raylib
            pkg-config
            just
            bear
            readline
            libbacktrace
            glfw3
          ];
        };
      });
}
