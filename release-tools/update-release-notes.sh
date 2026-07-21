set -eEuo pipefail

release_plz_releases_json="${RELEASE_PLZ_RELEASES_JSON:?RELEASE_PLZ_RELEASES_JSON is required}"
cargo_bin="${X52_CARGO:-cargo}"
gh_bin="${X52_GH:-gh}"
workspace_metadata="$("$cargo_bin" metadata --format-version=1 --no-deps)"

package_dir_for() {
    local package_name="$1"
    local manifest_path

    manifest_path="$(
        printf '%s\n' "$workspace_metadata" \
            | jq -r --arg package_name "$package_name" '.packages[] | select(.name == $package_name) | .manifest_path' \
            | head -n 1
    )"

    if [[ -z "$manifest_path" || "$manifest_path" == "null" ]]; then
        echo "Could not determine package directory for $package_name" >&2
        return 1
    fi

    dirname "$manifest_path"
}

update_release_notes() {
    local package_dir="$1"
    local version="$2"
    local tag="$3"
    local changelog_file="${package_dir}/CHANGELOG.md"
    local notes

    if [[ ! -f "$changelog_file" ]]; then
        echo "Skipping ${tag}: no ${changelog_file}"
        return 0
    fi

    echo "Updating ${tag} using ${changelog_file}"

    notes="$(
        awk -v version="$version" '
            $0 == "## " version {
                in_section = 1
                next
            }

            in_section && /^## / {
                exit
            }

            in_section {
                lines[++count] = $0
            }

            END {
                first = 1
                while (first <= count && lines[first] ~ /^[[:space:]]*$/) {
                    first++
                }

                last = count
                while (last >= first && lines[last] ~ /^[[:space:]]*$/) {
                    last--
                }

                for (i = first; i <= last; i++) {
                    print lines[i]
                }
            }
        ' "$changelog_file"
    )"

    if [[ -z "${notes//[[:space:]]/}" ]]; then
        notes="- No significant changes since the previous release."
    fi

    "$gh_bin" release edit "$tag" --notes="$notes"
}

while IFS=$'\t' read -r name version tag; do
    package_dir="$(package_dir_for "$name")"
    update_release_notes "$package_dir" "$version" "$tag"
done < <(printf '%s\n' "$release_plz_releases_json" | jq -r '.[] | [.package_name, .version, .tag] | @tsv')
