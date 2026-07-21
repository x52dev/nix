set -eEuo pipefail

release_plz_pr_json="${RELEASE_PLZ_PR_JSON:?RELEASE_PLZ_PR_JSON is required}"
cargo_bin="${X52_CARGO:-cargo}"
gh_bin="${X52_GH:-gh}"
git_bin="${X52_GIT:-git}"

pr_number="$(printf '%s\n' "$release_plz_pr_json" | jq -r '.number')"

if [[ -n "$pr_number" && "$pr_number" != "null" ]]; then
    "$gh_bin" pr checkout "$pr_number"
fi

workspace_metadata="$("$cargo_bin" metadata --format-version=1 --no-deps)"
changed_paths=()

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

bump_changelog_version() {
    local package_dir="$1"
    local version="$2"
    local changelog_file="${package_dir}/CHANGELOG.md"
    local readme_file="${package_dir}/README.md"
    local unreleased_line
    local next_heading_line
    local previous_version
    local change_chunk_file
    local line_count

    if [[ ! -f "$changelog_file" ]]; then
        echo "Skipping ${package_dir}: no CHANGELOG.md"
        return 0
    fi

    if grep -q "^## ${version}$" "$changelog_file"; then
        echo "Skipping ${changelog_file}: already contains ${version}"
        return 0
    fi

    unreleased_line="$(awk '/^## Unreleased$/ { print NR; exit }' "$changelog_file")"
    if [[ -z "$unreleased_line" ]]; then
        echo "Skipping ${changelog_file}: no '## Unreleased' heading"
        return 0
    fi

    next_heading_line="$(
        awk -v start="$unreleased_line" 'NR > start && /^## / { print NR; exit }' "$changelog_file"
    )"
    line_count="$(wc -l < "$changelog_file" | awk '{ print $1 }')"
    if [[ -z "$next_heading_line" ]]; then
        next_heading_line=$((line_count + 1))
    fi

    previous_version="$(sed -n "${next_heading_line}s/^## //p" "$changelog_file")"
    change_chunk_file="$(mktemp)"

    echo "${changelog_file} -> ${version}"

    sed -n "$((unreleased_line + 1)),$((next_heading_line - 1))p" "$changelog_file" \
        | awk '
            {
                lines[NR] = $0
            }
            END {
                first = 1
                while (first <= NR && lines[first] ~ /^[[:space:]]*$/) {
                    first++
                }

                last = NR
                while (last >= first && lines[last] ~ /^[[:space:]]*$/) {
                    last--
                }

                for (i = first; i <= last; i++) {
                    print lines[i]
                }
            }
        ' >"$change_chunk_file"

    if [[ "$(wc -w "$change_chunk_file" | awk '{ print $1 }')" == "0" ]]; then
        printf '%s\n' "- No significant changes since \`${previous_version}\`." >"$change_chunk_file"
    fi

    (
        sed -n "1,${unreleased_line}p" "$changelog_file"
        echo
        echo "## $version"
        echo
        cat "$change_chunk_file"
        echo
        sed -n "${next_heading_line},${line_count}p" "$changelog_file"
    ) >"$changelog_file.bak"

    mv "$changelog_file.bak" "$changelog_file"
    rm -f "$change_chunk_file"
    changed_paths+=("$changelog_file")

    if [[ -f "$readme_file" && -n "$previous_version" ]]; then
        sed -i.bak -E "s#([=/])${previous_version}([/)])#\\1${version}\\2#g" "$readme_file"
        rm -f "${readme_file}.bak"
        changed_paths+=("$readme_file")
    fi
}

while IFS=$'\t' read -r name version; do
    package_dir="$(package_dir_for "$name")"
    bump_changelog_version "$package_dir" "$version"
done < <(printf '%s\n' "$release_plz_pr_json" | jq -r '.releases[] | [.package_name, .version] | @tsv')

if [[ -n "$pr_number" && "$pr_number" != "null" && ${#changed_paths[@]} -gt 0 ]]; then
    "$git_bin" add -- "${changed_paths[@]}"

    if ! "$git_bin" diff --cached --quiet; then
        "$git_bin" commit -m "docs: update changelog versions"
        "$git_bin" push
    fi
fi
