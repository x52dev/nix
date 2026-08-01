set -eEuo pipefail

release_plz_releases_json="${1:?release-plz releases JSON is required}"
marker="<!-- x52-release-assets-uploaded -->"
commit_sha="${2:-${GITHUB_SHA:-}}"
gh_bin="${X52_GH:-gh}"

if [[ -z "$commit_sha" ]]; then
    echo "No commit SHA provided; skipping release assets comment"
    exit 0
fi

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
    echo "GITHUB_REPOSITORY is not set; skipping release assets comment"
    exit 0
fi

pr_number="$(
    "$gh_bin" api \
        "/repos/${GITHUB_REPOSITORY}/commits/${commit_sha}/pulls" \
        --jq '[.[] | select(.merged_at != null)] | sort_by(.number) | last | .number // empty'
)"

if [[ -z "$pr_number" ]]; then
    echo "No merged PR found for ${commit_sha}; skipping release assets comment"
    exit 0
fi

release_lines=""

while read -r release; do
    tag="$(printf '%s\n' "$release" | jq -r '.tag')"
    version="$(printf '%s\n' "$release" | jq -r '.version')"
    package_name="$(printf '%s\n' "$release" | jq -r '.package_name')"
    release_url="$("$gh_bin" release view "$tag" --json url --jq '.url')"

    release_lines+="- ${package_name} ${version}: ${release_url}"$'\n'
done < <(printf '%s\n' "$release_plz_releases_json" | jq -c '.[]')

if [[ -z "$release_lines" ]]; then
    echo "No release URLs found; skipping release assets comment"
    exit 0
fi

body="${marker}"$'\n'"Release assets uploaded:"$'\n\n'"${release_lines}"

existing_comment_id="$(
    "$gh_bin" api \
        "/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/comments" \
        --paginate \
        --jq ".[] | select(.body | contains(\"${marker}\")) | .id" \
        | tail -n 1
)"

if [[ -n "$existing_comment_id" ]]; then
    "$gh_bin" api \
        --method PATCH \
        "/repos/${GITHUB_REPOSITORY}/issues/comments/${existing_comment_id}" \
        -f body="$body" \
        >/dev/null
else
    "$gh_bin" pr comment "$pr_number" --body "$body"
fi
