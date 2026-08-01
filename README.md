# x52 Nix

Shared Nix packages and [Just](https://just.systems/) fragments for x52 projects.

## Packages

### `x52-just`

Contains reusable Just fragments. The package currently exports `rust.just`, which defines:

- `msrv`: the lowest `rust-version` declared by a Cargo workspace member, normalized to three components; for example, `1.82` becomes `1.82.0`.
- `msrv_rustup`: the same version prefixed with `+` for rustup-aware Cargo commands; for example, `+1.82.0`.

The lookup uses `cargo metadata --no-deps`, ignores non-workspace packages, and fails if Cargo metadata cannot be read or no workspace member declares `rust-version`.

### `x52-release-tools`

Contains release-plz post-processing commands:

- `x52-bump-changelogs` checks out a release-plz pull request, adds the released versions to crate changelogs, updates README version links, and pushes a commit when anything changed.
- `x52-update-release-notes` copies the matching changelog sections into GitHub releases.
- `x52-comment-release-pr` adds or updates a draft-release link comment on the merged release pull request.
- `x52-comment-release-assets-uploaded` adds or updates a comment after the release assets are uploaded.

The commands expect `cargo` to already be available. Git, GitHub CLI, jq, and the required shell utilities are supplied by the Nix package.

## Usage

Build the Just package to a stable project-local link:

```sh
nix build github:x52dev/nix#x52-just --out-link .x52-just
```

Add `.x52-just` to the consuming project's `.gitignore`, then import the fragment from its `justfile`:

```just
import '.x52-just/rust.just'

show-msrv:
    @echo {{msrv}}

check-msrv:
    cargo {{msrv_rustup}} check --workspace
```

The consuming environment must provide `just`, `cargo`, and `jq`. The `msrv_rustup` form also expects a rustup-managed toolchain.

## Flake-parts module

`flakeModules.default` and `flakeModules.justRust` provide `x52.justRust.shellHook`. Add it to a development shell to create an ignored `.toolchain/rust.just` symlink when the shell starts. The module does not select or add a `just` package.

```nix
imports = [ inputs.x52.flakeModules.default ];

perSystem = { config, pkgs, ... }: {
  devShells.default = pkgs.mkShell {
    packages = [
      pkgs.cargo
      pkgs.just
    ];

    shellHook = config.x52.justRust.shellHook;
  };
};
```

For an existing hook, append `config.x52.justRust.shellHook` to it. Set `x52.justRust.directory` in `perSystem` when a project needs another directory.

The shell hook runs for `nix develop`, direnv, and the `nicknovitski/nix-develop` GitHub Action. Add the directory to `.gitignore`:

```gitignore
/.toolchain/
```

To pin this repository in a consuming flake, add it as an input:

```nix
inputs.x52 = {
  url = "github:x52dev/nix";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-parts.follows = "flake-parts";
};
```

With flake-parts, re-export `x52-just` or add the release tools to a development shell:

```nix
perSystem = { pkgs, inputs', ... }: {
  packages.x52-just = inputs'.x52.packages.x52-just;

  devShells.default = pkgs.mkShell {
    packages = [
      inputs'.x52.packages.x52-release-tools
    ];
  };
};
```

Create the local Just link from the pinned input with:

```sh
nix build .#x52-just --out-link .x52-just
```

Just import paths are relative to the importing file, so run the command from the project root and keep the out-link alongside the root `justfile`.

For GitHub Actions, enter the development shell before invoking the release commands:

```yaml
- name: Enter Nix devshell
  uses: nicknovitski/nix-develop@9be7cfb4b10451d3390a75dc18ad0465bed4932a # v1.2.1
```

Pass release-plz output through `RELEASE_PLZ_PR_JSON` or `RELEASE_PLZ_RELEASES_JSON`, and provide `GH_TOKEN` for GitHub mutations.

Use a repository-specific HTML marker when posting release comments. It makes retries update the existing comment instead of creating another one:

```sh
x52-comment-release-pr "$RELEASE_PLZ_RELEASES_JSON" '<!-- example:draft-release-link -->'
x52-comment-release-assets-uploaded "$RELEASE_PLZ_RELEASES_JSON" '<!-- example:release-assets-uploaded -->'
```

Both commands accept an optional third argument for the merge commit SHA. Without it, they use `GITHUB_SHA`.

## Development

Enter the development shell with `nix develop` or use direnv with the included `.envrc`.

```sh
just fmt
just check
nix build .#x52-just
nix build .#x52-release-tools
```
