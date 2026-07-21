{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      perSystem =
        {
          config,
          inputs',
          system,
          pkgs,
          lib,
          ...
        }:
        {
          packages.x52-just = pkgs.runCommand "x52-just" { } ''
            mkdir -p "$out"
            cp ${./just/src}/*.just "$out/"
          '';

          checks = {
            formatting =
              pkgs.runCommand "check-formatting"
                {
                  nativeBuildInputs = [
                    config.formatter
                    pkgs.just
                  ];
                }
                ''
                  cp -R ${inputs.self} source
                  chmod -R u+w source

                  treefmt --ci --tree-root source
                  just --check --fmt --justfile source/justfile
                  just --check --fmt --justfile source/just/src/rust.just
                  touch "$out"
                '';

            rust-just =
              let
                testJustfile = pkgs.writeText "justfile" ''
                  import '${config.packages.x52-just}/rust.just'
                '';
              in
              pkgs.runCommand "check-rust-just"
                {
                  nativeBuildInputs = [
                    pkgs.cargo
                    pkgs.jq
                    pkgs.just
                  ];
                }
                ''
                  cp -R ${./tests/fixtures/multiple-msrvs} multiple-msrvs
                  chmod -R u+w multiple-msrvs
                  cp ${testJustfile} multiple-msrvs/justfile

                  actual_msrv="$(just --justfile multiple-msrvs/justfile --evaluate msrv)"
                  test "$actual_msrv" = "1.70.0"

                  actual_msrv_rustup="$(just --justfile multiple-msrvs/justfile --evaluate msrv_rustup)"
                  test "$actual_msrv_rustup" = "+1.70.0"

                  cp -R ${./tests/fixtures/missing-msrv} missing-msrv
                  chmod -R u+w missing-msrv
                  cp ${testJustfile} missing-msrv/justfile

                  if just --justfile missing-msrv/justfile --evaluate msrv; then
                    echo "expected a workspace without rust-version to fail" >&2
                    exit 1
                  fi

                  mkdir no-workspace
                  cp ${testJustfile} no-workspace/justfile

                  if just --justfile no-workspace/justfile --evaluate msrv; then
                    echo "expected Cargo metadata failure to propagate" >&2
                    exit 1
                  fi

                  touch "$out"
                '';
          };

          devShells.default = pkgs.mkShellNoCC {
            packages = [
              config.formatter
              pkgs.just
            ];
          };

          formatter = pkgs.nixfmt-tree;
        };
    };
}
