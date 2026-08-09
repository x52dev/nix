{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      justRustModule = import ./modules/rust-just.nix;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.flakeModules
        justRustModule
      ];

      flake.flakeModules = {
        default = justRustModule;
        justRust = justRustModule;
      };

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
        let
          x52Just = pkgs.callPackage ./just/package.nix { };
          initToolchain = pkgs.callPackage ./just/init-toolchain.nix {
            inherit x52Just;
          };

          x52-bump-changelogs = pkgs.writeShellApplication {
            name = "x52-bump-changelogs";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gawk
              pkgs.gh
              pkgs.git
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
            ];
            text = builtins.readFile ./release-tools/bump-changelogs.bash;
          };

          x52-update-release-notes = pkgs.writeShellApplication {
            name = "x52-update-release-notes";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gawk
              pkgs.gh
              pkgs.git
              pkgs.jq
            ];
            text = builtins.readFile ./release-tools/update-release-notes.bash;
          };

          x52-comment-release-pr = pkgs.writeShellApplication {
            name = "x52-comment-release-pr";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gh
              pkgs.jq
            ];
            text = builtins.readFile ./release-tools/comment-release-pr.bash;
          };

          x52-comment-release-assets-uploaded = pkgs.writeShellApplication {
            name = "x52-comment-release-assets-uploaded";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gh
              pkgs.jq
            ];
            text = builtins.readFile ./release-tools/comment-release-assets-uploaded.bash;
          };

          x52-release-tools = pkgs.symlinkJoin {
            name = "x52-release-tools";
            paths = [
              x52-bump-changelogs
              x52-update-release-notes
              x52-comment-release-pr
              x52-comment-release-assets-uploaded
            ];
          };
        in
        {
          packages = {
            x52-just = x52Just;

            inherit x52-release-tools;
          };

          checks = {
            release-tools =
              pkgs.runCommand "x52-release-tools-test"
                {
                  nativeBuildInputs = [
                    pkgs.bash
                    pkgs.diffutils
                    pkgs.gnugrep
                    x52-release-tools
                  ];
                  BASH_BIN = "${pkgs.bash}/bin/bash";
                }
                ''
                  bash ${./release-tools/test.bash}
                  touch "$out"
                '';

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

            rust-just-module =
              pkgs.runCommand "check-rust-just-module"
                {
                  nativeBuildInputs = [
                    initToolchain
                    pkgs.coreutils
                    pkgs.just
                  ];
                }
                ''
                  mkdir toolchain-test
                  cd toolchain-test

                  x52-init-rust-just
                  test -L .toolchain/rust.just
                  test "$(readlink .toolchain/rust.just)" = "${x52Just}/rust.just"

                  printf "import '.toolchain/rust.just'\n" > justfile
                  just --justfile justfile --list > /dev/null
                  touch "$out"
                '';
          };

          devShells.default = pkgs.mkShellNoCC {
            packages = [
              config.formatter
              pkgs.just
              x52-release-tools
            ];
          };

          formatter = pkgs.nixfmt-tree;
        };
    };
}
