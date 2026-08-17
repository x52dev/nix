set -euo pipefail
shopt -s inherit_errexit

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fixture_root="$test_root/project"
tap_root="$test_root/homebrew-tap"
fake_bin="$test_root/bin"
command_log="$test_root/commands.log"
comment_log="$test_root/comments.log"
release_attempts_file="$test_root/release-attempts"
bash_bin="${BASH_BIN:?BASH_BIN is required}"
mkdir -p "$fixture_root" "$tap_root/Formula" "$fake_bin"

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

cat >"$tap_root/Formula/demo-formula.rb" <<'EOF'
class Demo < Formula
  # x52-release-tools: begin metadata
  stale metadata
  # x52-release-tools: end metadata

  on_macos do
    # x52-release-tools: begin macOS artifacts
    stale macOS artifacts
    # x52-release-tools: end macOS artifacts

    test do
      assert_match "custom test", shell_output("#{bin}/demo-formula verify")
    end
  end
end
EOF

cat >"$tap_root/Formula/manual-demo.rb" <<'EOF'
class ManualDemo < Formula
  # x52-release-tools: begin version
  version "1.0.0"
  # x52-release-tools: end version

  on_macos do
    # x52-release-tools: begin MACOS artifacts
    stale macOS artifacts
    # x52-release-tools: end MACOS artifacts
  end

  on_linux do
    # x52-release-tools: begin LiNuX artifacts
    stale Linux artifacts
    # x52-release-tools: end LiNuX artifacts

    test do
      assert_match "manual test", shell_output("#{bin}/manual-demo verify")
    end
  end
end
EOF

printf '#!%s\n' "$bash_bin" >"$fake_bin/cargo"
cat >>"$fake_bin/cargo" <<'EOF'
set -euo pipefail
shopt -s inherit_errexit
[[ "$*" == "metadata --format-version=1 --no-deps" ]]
printf '%s\n' "{\"packages\":[{\"name\":\"demo\",\"version\":\"1.1.0\",\"description\":\"Demo \\\"CLI\\\"\",\"homepage\":null,\"repository\":\"https://github.com/example/source\",\"license\":\"MIT OR Apache-2.0\",\"manifest_path\":\"${FIXTURE_ROOT}/Cargo.toml\"},{\"name\":\"manual-release\",\"version\":\"1.2.0\",\"description\":\"Manual demo\",\"homepage\":\"https://example.com/manual\",\"repository\":null,\"license\":\"MIT\",\"manifest_path\":\"${FIXTURE_ROOT}/Cargo.toml\"}]}"
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
    'release download demo-v1.1.0 --repo example/source --pattern demo-asset-aarch64-apple-darwin.tar.gz.sha256 --dir '*)
        ;;
    'release download demo-v1.1.0 --repo example/source --pattern demo-asset-aarch64-apple-darwin.sha256 --dir '*)
        checksum_dir="${*: -1}"
        printf 'arm-checksum  demo-asset-aarch64-apple-darwin.tar.gz\n' >"$checksum_dir/demo-asset-aarch64-apple-darwin.sha256"
        ;;
    'release download demo-v1.1.0 --repo example/source --pattern demo-asset-x86_64-apple-darwin.tar.gz.sha256 --dir '*)
        checksum_dir="${*: -1}"
        printf 'intel-checksum  demo-asset-x86_64-apple-darwin.tar.gz\n' >"$checksum_dir/demo-asset-x86_64-apple-darwin.tar.gz.sha256"
        ;;
    'release download demo-v1.2.0 --repo example/manual --pattern manual-asset-aarch64-apple-darwin.tar.gz.sha256 --dir '*)
        checksum_dir="${*: -1}"
        printf 'manual-arm-checksum  manual-asset-aarch64-apple-darwin.tar.gz\n' >"$checksum_dir/manual-asset-aarch64-apple-darwin.tar.gz.sha256"
        ;;
    'release download demo-v1.2.0 --repo example/manual --pattern manual-asset-x86_64-apple-darwin.tar.gz.sha256 --dir '*)
        checksum_dir="${*: -1}"
        printf 'manual-intel-checksum  manual-asset-x86_64-apple-darwin.tar.gz\n' >"$checksum_dir/manual-asset-x86_64-apple-darwin.tar.gz.sha256"
        ;;
    'release download demo-v1.2.0 --repo example/manual --pattern manual-asset-aarch64-unknown-linux-gnu.tar.gz.sha256 --dir '*)
        checksum_dir="${*: -1}"
        printf 'manual-linux-arm-checksum  manual-asset-aarch64-unknown-linux-gnu.tar.gz\n' >"$checksum_dir/manual-asset-aarch64-unknown-linux-gnu.tar.gz.sha256"
        ;;
    'release download demo-v1.2.0 --repo example/manual --pattern manual-asset-x86_64-unknown-linux-gnu.tar.gz.sha256 --dir '*)
        checksum_dir="${*: -1}"
        printf 'manual-linux-intel-checksum  manual-asset-x86_64-unknown-linux-gnu.tar.gz\n' >"$checksum_dir/manual-asset-x86_64-unknown-linux-gnu.tar.gz.sha256"
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
if [[ "$*" == "diff --cached --quiet" || "$*" == *"diff --quiet --"* ]]; then
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
export X52_HOMEBREW_TAP_DIRECTORY="$tap_root"

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

RUNNER_DEBUG=1 x52-update-homebrew-tap \
    --releases "$RELEASE_PLZ_RELEASES_JSON" \
    --package demo \
    --formula demo-formula \
    --asset-prefix demo-asset \
    --source-repository example/source \
    --tap example/tap \
    --base release >"$test_root/homebrew-updater.log"

grep -Fq 'x52-update-homebrew-tap: Updating demo-formula to 1.1.0 from example/source release demo-v1.1.0' "$test_root/homebrew-updater.log"
grep -Fq 'x52-update-homebrew-tap: Downloading release checksums for macos' "$test_root/homebrew-updater.log"
grep -Fq 'x52-update-homebrew-tap: Running '"$fake_bin"'/gh release download demo-v1.1.0 --repo example/source' "$test_root/homebrew-updater.log"
grep -Fq 'x52-update-homebrew-tap: Creating pull request in example/tap' "$test_root/homebrew-updater.log"
grep -Fq 'version "1.1.0"' "$tap_root/Formula/demo-formula.rb"
grep -Fq 'sha256 "arm-checksum"' "$tap_root/Formula/demo-formula.rb"
grep -Fq 'sha256 "intel-checksum"' "$tap_root/Formula/demo-formula.rb"
grep -Fq 'desc "Demo \"CLI\""' "$tap_root/Formula/demo-formula.rb"
grep -Fq 'homepage "https://github.com/example/source"' "$tap_root/Formula/demo-formula.rb"
grep -Fq 'license "MIT OR Apache-2.0"' "$tap_root/Formula/demo-formula.rb"
grep -Fq 'assert_match "custom test", shell_output("#{bin}/demo-formula verify")' "$tap_root/Formula/demo-formula.rb"
grep -Fq '# x52-release-tools: begin macos artifacts' "$tap_root/Formula/demo-formula.rb"
grep -Fq 'gh <pr> <create> <--repo> <example/tap> <--base> <release> <--head> <release/homebrew-demo-formula-1.1.0>' "$command_log"
grep -Fq 'git <-C> <'"$tap_root"'> <config> <user.name> <x52-homebrew-tap-updater[bot]>' "$command_log"
grep -Fq 'git <-C> <'"$tap_root"'> <config> <user.email> <315069165+x52-homebrew-tap-updater[bot]@users.noreply.github.com>' "$command_log"
grep -Fq 'git <-C> <'"$tap_root"'> <commit> <-m> <chore: update demo-formula to 1.1.0>' "$command_log"
grep -Fq 'git <-C> <'"$tap_root"'> <push> <--set-upstream> <origin> <release/homebrew-demo-formula-1.1.0>' "$command_log"
if grep -Fq 'gh <auth> <setup-git>' "$command_log"; then
    echo "Expected the updater to use the tap checkout's Git credentials" >&2
    exit 1
fi

x52-update-homebrew-tap \
    --tag demo-v1.2.0 \
    --version 1.2.0 \
    --package manual-release \
    --formula manual-demo \
    --asset-prefix manual-asset \
    --source-repository example/manual

grep -Fq 'version "1.2.0"' "$tap_root/Formula/manual-demo.rb"
grep -Fq 'sha256 "manual-arm-checksum"' "$tap_root/Formula/manual-demo.rb"
grep -Fq 'sha256 "manual-intel-checksum"' "$tap_root/Formula/manual-demo.rb"
grep -Fq 'sha256 "manual-linux-arm-checksum"' "$tap_root/Formula/manual-demo.rb"
grep -Fq 'sha256 "manual-linux-intel-checksum"' "$tap_root/Formula/manual-demo.rb"
grep -Fq 'assert_match "manual test", shell_output("#{bin}/manual-demo verify")' "$tap_root/Formula/manual-demo.rb"
grep -Fq '# x52-release-tools: begin macos artifacts' "$tap_root/Formula/manual-demo.rb"
grep -Fq '# x52-release-tools: begin linux artifacts' "$tap_root/Formula/manual-demo.rb"

unset X52_HOMEBREW_TAP_DIRECTORY
if x52-update-homebrew-tap \
    --tag demo-v1.2.0 \
    --version 1.2.0 \
    --package manual-release \
    --source-repository example/manual >"$test_root/missing-tap-directory.log" 2>&1; then
    echo "Expected a missing Homebrew tap checkout to fail" >&2
    exit 1
fi
grep -Fq -- '--tap-directory or X52_HOMEBREW_TAP_DIRECTORY is required' "$test_root/missing-tap-directory.log"

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
