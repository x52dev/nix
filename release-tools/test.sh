set -euo pipefail

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fixture_root="$test_root/project"
fake_bin="$test_root/bin"
command_log="$test_root/commands.log"
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
[[ "$*" == "metadata --format-version=1 --no-deps" ]]
printf '{"packages":[{"name":"demo","manifest_path":"%s/Cargo.toml"}]}\n' "$FIXTURE_ROOT"
EOF

printf '#!%s\n' "$bash_bin" >"$fake_bin/gh"
cat >>"$fake_bin/gh" <<'EOF'
set -euo pipefail
printf 'gh' >>"$COMMAND_LOG"
printf ' <%s>' "$@" >>"$COMMAND_LOG"
printf '\n' >>"$COMMAND_LOG"
EOF

printf '#!%s\n' "$bash_bin" >"$fake_bin/git"
cat >>"$fake_bin/git" <<'EOF'
set -euo pipefail
if [[ "$*" == "diff --cached --quiet" ]]; then
    exit 1
fi
printf 'git' >>"$COMMAND_LOG"
printf ' <%s>' "$@" >>"$COMMAND_LOG"
printf '\n' >>"$COMMAND_LOG"
EOF

chmod +x "$fake_bin/cargo" "$fake_bin/gh" "$fake_bin/git"

export COMMAND_LOG="$command_log"
export FIXTURE_ROOT="$fixture_root"
export X52_CARGO="$fake_bin/cargo"
export X52_GH="$fake_bin/gh"
export X52_GIT="$fake_bin/git"

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
