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
