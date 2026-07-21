# x52 Nix

Shared Nix packages and [Just](https://just.systems/) fragments for x52 projects.

## Packages

### `x52-just`

Contains reusable Just fragments. The package currently exports `rust.just`, which defines:

- `msrv`: the lowest `rust-version` declared by a Cargo workspace member, normalized to three components; for example, `1.82` becomes `1.82.0`.
- `msrv_rustup`: the same version prefixed with `+` for rustup-aware Cargo commands; for example, `+1.82.0`.

The lookup uses `cargo metadata --no-deps`, ignores non-workspace packages, and fails if Cargo metadata cannot be read or no workspace member declares `rust-version`.

## Usage

Build the package to a stable project-local link:

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
inputs.x52-nix.url = "github:x52dev/nix";
```

With flake-parts, the package can be re-exported for the build command above:

```nix
perSystem = { inputs', ... }: {
  packages.x52-just = inputs'.x52-nix.packages.x52-just;
};
```

Then create the local link from the pinned input with:

```sh
nix build .#x52-just --out-link .x52-just
```

Just import paths are relative to the importing file, so run the command from the project root and keep the out-link alongside the root `justfile`.

## Development

Enter the development shell with `nix develop` or use direnv with the included `.envrc`.

```sh
just fmt
nix flake check
nix build .#x52-just
```
