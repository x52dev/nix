# Lowest declared Rust version among workspace members.
msrv := ```
    metadata="$(cargo metadata --format-version=1 --no-deps)" &&
        printf '%s\n' "$metadata" |
        jq -er '
            .workspace_members as $workspace_members
            | [
                .packages[]
                | select(.id as $id | $workspace_members | index($id))
                | select(.rust_version != null)
                | .rust_version
            ]
            | if length == 0 then
                error("no workspace package declares rust-version")
              else
                min_by(split(".") | map(tonumber))
              end
            | split(".")
            | if length == 2 then . + ["0"] else . end
            | join(".")
        '
```
msrv_rustup := "+" + msrv

# Nightly toolchain used by external type checks.
external-types-toolchain := "nightly-2026-03-20"

# Check public APIs for exposed external types.
check-external-types all-features="":
    #!/usr/bin/env bash
    set -eEuo pipefail
    cargo metadata --frozen --no-deps --format-version=1 \
        | jq -r '.workspace_members as $members | .packages[] | select(.id as $id | $members | index($id)) | select(any(.targets[]; .kind | index("lib"))) | .manifest_path' \
        | while read -r manifest_path; do
            echo "Checking external types: ${manifest_path}"
            args=(--manifest-path "${manifest_path}")
            if [[ "{{ all-features }}" == "--all-features" ]]; then
                args+=(--all-features)
            fi
            cargo +{{ external-types-toolchain }} check-external-types "${args[@]}"
        done
