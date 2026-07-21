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

To pin this repository in a consuming flake, add it as an input:

```nix
inputs.x52-nix = {
  url = "github:x52dev/nix";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-parts.follows = "flake-parts";
};
```

With flake-parts, re-export `x52-just` or add the release tools to a development shell:

```nix
perSystem = { pkgs, inputs', ... }: {
  packages.x52-just = inputs'.x52-nix.packages.x52-just;

  devShells.default = pkgs.mkShell {
    packages = [
      inputs'.x52-nix.packages.x52-release-tools
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

## Development

Enter the development shell with `nix develop` or use direnv with the included `.envrc`.

```sh
just fmt
just check
nix build .#x52-just
nix build .#x52-release-tools
```
