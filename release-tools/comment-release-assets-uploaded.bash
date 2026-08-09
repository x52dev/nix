set -eEuo pipefail
shopt -s inherit_errexit

release_plz_releases_json="${1:?release-plz releases JSON is required}"
marker="<!-- x52-release-assets-uploaded -->"
commit_sha="${2:-${GITHUB_SHA:-}}"
gh_bin="${X52_GH:-gh}"
sleep_bin="${X52_SLEEP:-sleep}"
max_release_lookup_attempts=5

log() {
    echo "x52-comment-release-assets-uploaded: $*"
}

if [[ -z "$commit_sha" ]]; then
    log "No commit SHA provided; skipping"
    exit 0
fi

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
    log "GITHUB_REPOSITORY is not set; skipping"
    exit 0
fi

if ! release_entries="$(
    printf '%s\n' "$release_plz_releases_json" | jq -c '
        if type == "array"
            and all(.[]; (.tag | type == "string") and (.version | type == "string") and (.package_name | type == "string"))
        then .[]
        else error("expected an array of releases with tag, version, and package_name")
        end
    '
)"; then
    log "Invalid release-plz releases JSON"
    exit 1
fi

pr_number="$(
    "$gh_bin" api \
        "/repos/${GITHUB_REPOSITORY}/commits/${commit_sha}/pulls" \
        --jq '[.[] | select(.merged_at != null)] | sort_by(.number) | last | .number // empty'
)"

if [[ -z "$pr_number" ]]; then
    log "No merged PR found for ${commit_sha}; skipping"
    exit 0
fi

log "Resolved commit ${commit_sha} to merged PR #${pr_number}"

release_lookup_delay=1
for ((release_lookup_attempt = 1; release_lookup_attempt <= max_release_lookup_attempts; release_lookup_attempt++)); do
    log "Fetching releases from /repos/${GITHUB_REPOSITORY}/releases (attempt ${release_lookup_attempt}/${max_release_lookup_attempts})"
    if ! releases_json="$(
        "$gh_bin" api --paginate "/repos/${GITHUB_REPOSITORY}/releases?per_page=100"
    )"; then
        retry_reason="Failed to fetch releases from /repos/${GITHUB_REPOSITORY}/releases"
    else
        if [[ "${RUNNER_DEBUG:-}" == "1" ]]; then
            log "GitHub releases API response:"
            printf '%s\n' "$releases_json" | jq -s .
        fi

        release_lines=""
        missing_tag=""
        while read -r release; do
            tag="$(printf '%s\n' "$release" | jq -r '.tag')"
            version="$(printf '%s\n' "$release" | jq -r '.version')"
            package_name="$(printf '%s\n' "$release" | jq -r '.package_name')"
            log "Resolving release tag ${tag}"
            release_info="$(
                printf '%s\n' "$releases_json" | jq -s -r --arg tag "$tag" \
                    '([.[][] | select(.tag_name == $tag)] | first) as $release
                    | if $release == null then empty else [$release.html_url, $release.draft] | @tsv end'
            )"

            if [[ -z "$release_info" ]]; then
                missing_tag="$tag"
                break
            fi

            IFS=$'\t' read -r release_url release_draft <<<"$release_info"
            release_type="published"
            if [[ "$release_draft" == "true" ]]; then
                release_type="draft"
            fi
            log "Resolved tag ${tag} to ${release_type} release ${release_url}"

            release_lines+="- ${package_name} ${version}: ${release_url}"$'\n'
        done <<<"$release_entries"

        if [[ -z "$missing_tag" ]]; then
            break
        fi

        retry_reason="No release with tag ${missing_tag} was returned by /repos/${GITHUB_REPOSITORY}/releases"
    fi

    if (( release_lookup_attempt == max_release_lookup_attempts )); then
        log "$retry_reason"
        exit 1
    fi

    log "${retry_reason}; retrying in ${release_lookup_delay}s"
    "$sleep_bin" "$release_lookup_delay"
    release_lookup_delay=$((release_lookup_delay * 2))
done

if [[ -z "$release_lines" ]]; then
    log "No releases in release-plz output; skipping"
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
    log "Updating release-assets comment on PR #${pr_number}"
    "$gh_bin" api \
        --method PATCH \
        "/repos/${GITHUB_REPOSITORY}/issues/comments/${existing_comment_id}" \
        -f body="$body" \
        >/dev/null
else
    log "Creating release-assets comment on PR #${pr_number}"
    "$gh_bin" pr comment "$pr_number" --body "$body"
fi
