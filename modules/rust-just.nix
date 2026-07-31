{ flake-parts-lib, lib, ... }:

{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.x52.justRust;
      x52Just = pkgs.callPackage ../just/package.nix { };
      initToolchain = pkgs.callPackage ../just/init-toolchain.nix {
        directory = cfg.directory;
        inherit x52Just;
      };
    in
    {
      options.x52.justRust = {
        directory = lib.mkOption {
          type = lib.types.str;
          default = ".toolchain";
          description = "Directory that contains the shared Just fragments.";
        };

        shellHook = lib.mkOption {
          type = lib.types.lines;
          readOnly = true;
          description = "Shell hook that creates the shared Rust Just fragment.";
        };
      };

      config.x52.justRust = {
        shellHook = ''
          ${initToolchain}/bin/x52-init-rust-just
        '';
      };
    }
  );
}
