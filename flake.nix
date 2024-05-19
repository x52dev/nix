{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      perSystem = { config, inputs', system, pkgs, lib, ... }: {
        packages.x52-just = pkgs.stdenv.mkDerivation {
          name = "x52-just";

          src = ./just/src;

          installPhase = ''
            mkdir -p $out
            cp $src/*.just $out/
          '';
        };

        devShells.default = pkgs.mkShellNoCC {
          packages = [
            config.formatter
            pkgs.just
          ];
        };

        formatter = pkgs.nixpkgs-fmt;
      };
    };
}
