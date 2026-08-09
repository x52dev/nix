set -euo pipefail
shopt -s inherit_errexit

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fixture_root="$test_root/project"
fake_bin="$test_root/bin"
command_log="$test_root/commands.log"
comment_log="$test_root/comments.log"
release_attempts_file="$test_root/release-attempts"
bash_bin="${BASH_BIN:?BASH_BIN is required}"
mkdir -p "$fixture_root" "$fake_bin"

cat >"$fixture_root/Cargo.toml" <<'EOF'
[package]
name = "demo"
version = "1.0.0"
EOF

cat >"$fixture_root/CHANGELOG.md" <<'EOF'
# Changelog

## Unreleased

- Added feature.

## 1.0.0

- Previous release.
EOF

cat >"$fixture_root/README.md" <<'EOF'
See https://docs.rs/demo/1.0.0/demo/ for documentation.
EOF

printf '#!%s\n' "$bash_bin" >"$fake_bin/cargo"
cat >>"$fake_bin/cargo" <<'EOF'
set -euo pipefail
shopt -s inherit_errexit
[[ "$*" == "metadata --format-version=1 --no-deps" ]]
printf '{"packages":[{"name":"demo","manifest_path":"%s/Cargo.toml"}]}\n' "$FIXTURE_ROOT"
EOF

printf '#!%s\n' "$bash_bin" >"$fake_bin/gh"
cat >>"$fake_bin/gh" <<'EOF'
set -euo pipefail
shopt -s inherit_errexit
printf 'gh' >>"$COMMAND_LOG"
printf ' <%s>' "$@" >>"$COMMAND_LOG"
printf '\n' >>"$COMMAND_LOG"

case "$*" in
    *'/commits/'*'/pulls'*)
        printf '42\n'
        ;;
    *'/releases?per_page=100'*)
        release_attempt=1
        if [[ -n "${RELEASE_ATTEMPTS_FILE:-}" ]]; then
            if [[ -f "$RELEASE_ATTEMPTS_FILE" ]]; then
                release_attempt="$(<"$RELEASE_ATTEMPTS_FILE")"
                release_attempt=$((release_attempt + 1))
            fi
            printf '%s\n' "$release_attempt" >"$RELEASE_ATTEMPTS_FILE"
        fi
        if [[ "${RELEASE_FOUND:-true}" == "true" && "$release_attempt" -ge "${RELEASE_AVAILABLE_AT_ATTEMPT:-1}" ]]; then
            printf '[{"tag_name":"other-v1.0.0","draft":false,"html_url":"https://github.com/example/demo/releases/tag/other-v1.0.0"}]\n'
            printf '[{"tag_name":"demo-v1.1.0","draft":true,"html_url":"https://github.com/example/demo/releases/tag/untagged-draft-release"},{"tag_name":"other-v1.1.0","draft":false,"html_url":"https://github.com/example/demo/releases/tag/other-v1.1.0"}]\n'
        else
            printf '[]\n[]\n'
        fi
        ;;
    *'/issues/'*'/comments'*)
        printf '%s\n' "${EXISTING_COMMENT_ID:-}"
        ;;
esac
EOF

printf '#!%s\n' "$bash_bin" >"$fake_bin/sleep"
cat >>"$fake_bin/sleep" <<'EOF'
set -euo pipefail
printf 'sleep' >>"$COMMAND_LOG"
printf ' <%s>' "$@" >>"$COMMAND_LOG"
printf '\n' >>"$COMMAND_LOG"
EOF

printf '#!%s\n' "$bash_bin" >"$fake_bin/git"
cat >>"$fake_bin/git" <<'EOF'
set -euo pipefail
shopt -s inherit_errexit
if [[ "$*" == "diff --cached --quiet" ]]; then
    exit 1
fi
printf 'git' >>"$COMMAND_LOG"
printf ' <%s>' "$@" >>"$COMMAND_LOG"
printf '\n' >>"$COMMAND_LOG"
EOF

chmod +x "$fake_bin/cargo" "$fake_bin/gh" "$fake_bin/git" "$fake_bin/sleep"

export COMMAND_LOG="$command_log"
export FIXTURE_ROOT="$fixture_root"
export X52_CARGO="$fake_bin/cargo"
export X52_GH="$fake_bin/gh"
export X52_GIT="$fake_bin/git"
export X52_SLEEP="$fake_bin/sleep"

cd "$fixture_root"

export RELEASE_PLZ_PR_JSON='{"number":42,"releases":[{"package_name":"demo","version":"1.1.0"}]}'
x52-bump-changelogs
x52-bump-changelogs

cat >"$test_root/expected-changelog.md" <<'EOF'
# Changelog

## Unreleased

## 1.1.0

- Added feature.

## 1.0.0

- Previous release.
EOF

diff -u "$test_root/expected-changelog.md" "$fixture_root/CHANGELOG.md"
grep -Fq 'https://docs.rs/demo/1.1.0/demo/' "$fixture_root/README.md"
[[ "$(grep -Fc 'git <commit> <-m> <docs: update changelog versions>' "$command_log")" == 1 ]]
grep -Fq 'gh <pr> <checkout> <42>' "$command_log"
grep -Fq 'git <push>' "$command_log"

export RELEASE_PLZ_RELEASES_JSON='[{"package_name":"demo","version":"1.1.0","tag":"demo-v1.1.0"}]'
x52-update-release-notes

grep -Fq 'gh <release> <edit> <demo-v1.1.0>' "$command_log"
grep -Fq '<--notes=- Added feature.>' "$command_log"

export GITHUB_REPOSITORY='example/demo'
x52-comment-release-pr "$RELEASE_PLZ_RELEASES_JSON" deadbeef >"$comment_log"
x52-comment-release-assets-uploaded "$RELEASE_PLZ_RELEASES_JSON" deadbeef >>"$comment_log"

grep -Fq 'gh <pr> <comment> <42> <--body> <<!-- x52-draft-release-link -->' "$command_log"
grep -Fq 'gh <pr> <comment> <42> <--body> <<!-- x52-release-assets-uploaded -->' "$command_log"
[[ "$(grep -Fc 'gh <api> <--paginate> </repos/example/demo/releases?per_page=100>' "$command_log")" == 2 ]]
grep -Fq 'untagged-draft-release' "$command_log"
grep -Fq 'Resolved tag demo-v1.1.0 to draft release https://github.com/example/demo/releases/tag/untagged-draft-release' "$comment_log"
grep -Fq 'Creating draft-release comment on PR #42' "$comment_log"
grep -Fq 'Creating release-assets comment on PR #42' "$comment_log"

export EXISTING_COMMENT_ID=99
x52-comment-release-pr "$RELEASE_PLZ_RELEASES_JSON" deadbeef >>"$comment_log"
x52-comment-release-assets-uploaded "$RELEASE_PLZ_RELEASES_JSON" deadbeef >>"$comment_log"

[[ "$(grep -Fc 'gh <api> <--method> <PATCH> </repos/example/demo/issues/comments/99>' "$command_log")" == 2 ]]
grep -Fq 'Updating draft-release comment on PR #42' "$comment_log"
grep -Fq 'Updating release-assets comment on PR #42' "$comment_log"

if x52-comment-release-pr '{"tag":"demo-v1.1.0"}' deadbeef >"$test_root/invalid-json.log" 2>&1; then
    echo "Expected invalid release-plz JSON to fail" >&2
    exit 1
fi
grep -Fq 'Invalid release-plz releases JSON' "$test_root/invalid-json.log"

if RELEASE_FOUND=false x52-comment-release-pr "$RELEASE_PLZ_RELEASES_JSON" deadbeef >"$test_root/missing-release-pr.log" 2>&1; then
    echo "Expected missing release to fail" >&2
    exit 1
else
    [[ "$?" == 1 ]]
fi
grep -Fq 'No release with tag demo-v1.1.0 was returned by /repos/example/demo/releases' "$test_root/missing-release-pr.log"

if RELEASE_FOUND=false x52-comment-release-assets-uploaded "$RELEASE_PLZ_RELEASES_JSON" deadbeef >"$test_root/missing-release-assets.log" 2>&1; then
    echo "Expected missing release to fail" >&2
    exit 1
else
    [[ "$?" == 1 ]]
fi
grep -Fq 'No release with tag demo-v1.1.0 was returned by /repos/example/demo/releases' "$test_root/missing-release-assets.log"

export RELEASE_PLZ_RELEASES_JSON='[{"package_name":"demo","version":"1.1.0","tag":"demo-v1.1.0"},{"package_name":"other","version":"1.1.0","tag":"other-v1.1.0"}]'
x52-comment-release-pr "$RELEASE_PLZ_RELEASES_JSON" deadbeef >>"$comment_log"
x52-comment-release-assets-uploaded "$RELEASE_PLZ_RELEASES_JSON" deadbeef >>"$comment_log"

[[ "$(grep -Fc 'gh <api> <--paginate> </repos/example/demo/releases?per_page=100>' "$command_log")" == 16 ]]

export RELEASE_ATTEMPTS_FILE="$release_attempts_file"
export RELEASE_AVAILABLE_AT_ATTEMPT=2
RUNNER_DEBUG=1 x52-comment-release-assets-uploaded "$RELEASE_PLZ_RELEASES_JSON" deadbeef >>"$comment_log"

[[ "$(<"$release_attempts_file")" == 2 ]]
grep -Fq 'No release with tag demo-v1.1.0 was returned by /repos/example/demo/releases; retrying in 1s' "$comment_log"
grep -Fq 'GitHub releases API response:' "$comment_log"
grep -Fq '"tag_name": "demo-v1.1.0"' "$comment_log"
[[ "$(grep -Fc 'sleep <1>' "$command_log")" == 3 ]]
[[ "$(grep -Fc 'gh <api> <--paginate> </repos/example/demo/releases?per_page=100>' "$command_log")" == 18 ]]

cat >"$fixture_root/CHANGELOG.md" <<'EOF'
# Changelog

## Unreleased

- Initial release.
EOF

export RELEASE_PLZ_PR_JSON='{"number":42,"releases":[{"package_name":"demo","version":"1.0.0"}]}'
x52-bump-changelogs

cat >"$test_root/expected-first-release-changelog.md" <<'EOF'
# Changelog

## Unreleased

## 1.0.0

- Initial release.

EOF

diff -u "$test_root/expected-first-release-changelog.md" "$fixture_root/CHANGELOG.md"
