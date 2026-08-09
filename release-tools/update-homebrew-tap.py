#!/usr/bin/env python3

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


ARTIFACT_TARGETS = {
    "linux": (("arm", "aarch64-unknown-linux-gnu"), ("intel", "x86_64-unknown-linux-gnu")),
    "macos": (("arm", "aarch64-apple-darwin"), ("intel", "x86_64-apple-darwin")),
}
MARKER = re.compile(
    r"^(?P<indent>\s*)#\s*x52-release-tools:\s*(?P<edge>begin|end)\s+(?:(?P<os>[a-z]+)\s+artifacts|(?P<kind>version|metadata))\s*$",
    re.IGNORECASE,
)


class UpdateError(Exception):
    pass


@dataclass(frozen=True)
class Release:
    tag: str
    version: str


@dataclass(frozen=True)
class Metadata:
    description: str
    homepage: str
    license: str
    version: str


def log(message: str) -> None:
    print(f"x52-update-homebrew-tap: {message}")


def debug(message: str) -> None:
    if os.environ.get("RUNNER_DEBUG") == "1":
        log(message)


def run(*command: str, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    debug(f"Running {shlex.join(command)}")
    result = subprocess.run(command, cwd=cwd, check=False, text=True, capture_output=True)
    if check and result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise UpdateError(f"{' '.join(command)} failed{': ' + detail if detail else ''}")
    return result


def ruby_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def release_from_arguments(args: argparse.Namespace) -> Release:
    if args.releases and (args.tag or args.version):
        raise UpdateError("Use either --releases or --tag with --version")

    if args.releases:
        try:
            releases = json.loads(args.releases)
        except json.JSONDecodeError as error:
            raise UpdateError(f"Invalid release-plz releases JSON: {error.msg}") from error

        if not isinstance(releases, list):
            raise UpdateError("release-plz releases JSON must be an array")

        matches = [release for release in releases if isinstance(release, dict) and release.get("package_name") == args.package]
        if len(matches) != 1:
            raise UpdateError(f"Expected exactly one release-plz entry for package {args.package}")

        release = matches[0]
        if not isinstance(release.get("tag"), str) or not isinstance(release.get("version"), str):
            raise UpdateError(f"Release-plz entry for package {args.package} must contain string tag and version fields")
        return Release(tag=release["tag"], version=release["version"])

    if args.tag and args.version:
        return Release(tag=args.tag, version=args.version)

    raise UpdateError("--releases or --tag with --version is required")


def cargo_metadata(package_name: str, expected_version: str) -> Metadata:
    cargo = os.environ.get("X52_CARGO", "cargo")
    result = run(cargo, "metadata", "--format-version=1", "--no-deps")

    try:
        packages = json.loads(result.stdout)["packages"]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        raise UpdateError("cargo metadata did not return packages") from error

    matches = [package for package in packages if package.get("name") == package_name]
    if len(matches) != 1:
        raise UpdateError(f"Expected exactly one Cargo package named {package_name}")

    package = matches[0]
    description = package.get("description")
    homepage = package.get("homepage") or package.get("repository")
    license_name = package.get("license")
    cargo_version = package.get("version")
    if not all(isinstance(value, str) and value for value in (description, homepage, license_name, cargo_version)):
        raise UpdateError(f"Cargo package {package_name} needs description, homepage or repository, license, and version metadata")
    if cargo_version != expected_version:
        raise UpdateError(f"Cargo package {package_name} has version {cargo_version}, but the release version is {expected_version}")

    return Metadata(description=description, homepage=homepage, license=license_name, version=cargo_version)


def marker(line: str) -> tuple[str, str, str] | None:
    match = MARKER.match(line.rstrip("\n"))
    if match is None:
        return None
    kind = (match.group("os") or match.group("kind")).lower()
    return match.group("edge").lower(), kind, match.group("indent")


def render_marker(indent: str, edge: str, kind: str) -> str:
    if kind in ARTIFACT_TARGETS:
        return f"{indent}# x52-release-tools: {edge} {kind} artifacts\n"
    return f"{indent}# x52-release-tools: {edge} {kind}\n"


def render_artifacts(indent: str, os_name: str, source_repository: str, release: Release, asset_prefix: str, checksums: dict[str, str]) -> list[str]:
    lines: list[str] = []
    for architecture, target in ARTIFACT_TARGETS[os_name]:
        archive = f"{asset_prefix}-{target}.tar.gz"
        url = f"https://github.com/{source_repository}/releases/download/{release.tag}/{archive}"
        lines.extend(
            [
                f"{indent}on_{architecture} do\n",
                f"{indent}  url {ruby_string(url)}\n",
                f"{indent}  sha256 {ruby_string(checksums[target])}\n",
                f"{indent}end\n",
                "\n",
            ]
        )
    return lines[:-1]


def render_formula(path: Path, source_repository: str, release: Release, asset_prefix: str, metadata: Metadata | None, checksums: dict[str, str]) -> None:
    source = path.read_text()
    lines = source.splitlines(keepends=True)
    output: list[str] = []
    blocks: dict[str, int] = {"version": 0, "metadata": 0, "linux": 0, "macos": 0}
    index = 0

    while index < len(lines):
        parsed = marker(lines[index])
        if parsed is None:
            output.append(lines[index])
            index += 1
            continue

        edge, kind, indent = parsed
        if edge == "end":
            raise UpdateError(f"Unexpected end marker in {path}: {lines[index].strip()}")
        if kind not in blocks:
            raise UpdateError(f"Unsupported generated block {kind} in {path}")
        blocks[kind] += 1
        if blocks[kind] != 1:
            raise UpdateError(f"Expected one {kind} block in {path}")

        end_index = index + 1
        while end_index < len(lines):
            end_marker = marker(lines[end_index])
            if end_marker is not None:
                end_edge, end_kind, _ = end_marker
                if end_edge == "begin":
                    raise UpdateError(f"Nested generated block in {path}")
                if end_kind != kind:
                    raise UpdateError(f"Mismatched end marker for {kind} block in {path}")
                break
            end_index += 1
        else:
            raise UpdateError(f"Missing end marker for {kind} block in {path}")

        output.append(render_marker(indent, "begin", kind))
        if kind == "version":
            output.append(f"{indent}version {ruby_string(release.version)}\n")
        elif kind == "metadata":
            if metadata is None:
                raise UpdateError(f"Metadata block in {path} requires Cargo metadata")
            output.extend(
                [
                    f"{indent}desc {ruby_string(metadata.description)}\n",
                    f"{indent}homepage {ruby_string(metadata.homepage)}\n",
                    f"{indent}version {ruby_string(metadata.version)}\n",
                    f"{indent}license {ruby_string(metadata.license)}\n",
                ]
            )
        else:
            output.extend(render_artifacts(indent, kind, source_repository, release, asset_prefix, checksums))
        output.append(render_marker(indent, "end", kind))
        index = end_index + 1

    if blocks["version"] + blocks["metadata"] != 1:
        raise UpdateError(f"Expected exactly one version or metadata block in {path}")
    if blocks["linux"] + blocks["macos"] == 0:
        raise UpdateError(f"Expected at least one OS artifacts block in {path}")

    path.write_text("".join(output))


def download_checksums(gh: str, source_repository: str, release: Release, asset_prefix: str, operating_systems: set[str]) -> dict[str, str]:
    checksums: dict[str, str] = {}
    with tempfile.TemporaryDirectory() as directory:
        checksum_directory = Path(directory)
        for os_name in operating_systems:
            for _, target in ARTIFACT_TARGETS[os_name]:
                archive = f"{asset_prefix}-{target}.tar.gz"
                checksum_names = (f"{archive}.sha256", f"{archive.removesuffix('.tar.gz')}.sha256")
                for checksum_name in checksum_names:
                    result = run(gh, "release", "download", release.tag, "--repo", source_repository, "--pattern", checksum_name, "--dir", str(checksum_directory), check=False)
                    checksum_path = checksum_directory / checksum_name
                    if result.returncode or not checksum_path.is_file():
                        continue
                    checksum_words = checksum_path.read_text().split(maxsplit=1)
                    if not checksum_words:
                        raise UpdateError(f"Release checksum for {archive} is empty")
                    checksums[target] = checksum_words[0]
                    break
                else:
                    raise UpdateError(f"Could not download a release checksum for {archive}")
    return checksums


def generated_os_blocks(path: Path) -> set[str]:
    return {parsed[1] for line in path.read_text().splitlines(keepends=True) if (parsed := marker(line)) and parsed[0] == "begin" and parsed[1] in ARTIFACT_TARGETS}


def has_metadata_block(path: Path) -> bool:
    for line in path.read_text().splitlines(keepends=True):
        parsed = marker(line)
        if parsed and parsed[:2] == ("begin", "metadata"):
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    release_input = parser.add_mutually_exclusive_group()
    release_input.add_argument("--releases", help="release-plz releases JSON")
    release_input.add_argument("--tag", help="release tag for a manual update")
    parser.add_argument("--version", help="release version for a manual update")
    parser.add_argument("--package", required=True, help="released Cargo package that owns the binary")
    parser.add_argument("--formula", help="formula name; defaults to --package")
    parser.add_argument("--asset-prefix", help="release archive prefix; defaults to --package")
    parser.add_argument("--source-repository", default=os.environ.get("GITHUB_REPOSITORY"), help="release repository")
    parser.add_argument("--tap", default=os.environ.get("X52_HOMEBREW_TAP_REPOSITORY", "x52dev/homebrew-tap"), help="Homebrew tap repository")
    parser.add_argument("--base", default="main", help="tap pull request base branch")
    parser.add_argument("--tap-directory", default=os.environ.get("X52_HOMEBREW_TAP_DIRECTORY"), help=argparse.SUPPRESS)
    args = parser.parse_args()

    try:
        release = release_from_arguments(args)
        if not args.source_repository:
            raise UpdateError("--source-repository or GITHUB_REPOSITORY is required")

        formula_name = args.formula or args.package
        asset_prefix = args.asset_prefix or args.package
        log(f"Updating {formula_name} to {release.version} from {args.source_repository} release {release.tag}")
        temporary_tap_directory = None
        if args.tap_directory:
            tap_directory = Path(args.tap_directory)
            log(f"Using Homebrew tap checkout {tap_directory}")
        else:
            temporary_tap_directory = tempfile.TemporaryDirectory()
            tap_directory = Path(temporary_tap_directory.name) / "homebrew-tap"
            gh = os.environ.get("X52_GH", "gh")
            git = os.environ.get("X52_GIT", "git")
            log(f"Cloning Homebrew tap {args.tap}")
            run(gh, "auth", "setup-git")
            run(git, "clone", f"https://github.com/{args.tap}.git", str(tap_directory))

        formula = tap_directory / "Formula" / f"{formula_name}.rb"
        if not formula.is_file():
            raise UpdateError(f"Formula {formula} does not exist")

        git = os.environ.get("X52_GIT", "git")
        gh = os.environ.get("X52_GH", "gh")
        branch = f"release/homebrew-{formula_name}-{release.version}"
        if run(git, "-C", str(tap_directory), "ls-remote", "--exit-code", "--heads", "origin", branch, check=False).returncode == 0:
            log(f"Reusing tap branch {branch}")
            run(git, "-C", str(tap_directory), "fetch", "origin", branch)
            run(git, "-C", str(tap_directory), "switch", "--track", f"origin/{branch}")
        else:
            log(f"Creating tap branch {branch}")
            run(git, "-C", str(tap_directory), "switch", "-c", branch)

        operating_systems = generated_os_blocks(formula)
        metadata = cargo_metadata(args.package, release.version) if has_metadata_block(formula) else None
        log(f"Downloading release checksums for {', '.join(sorted(operating_systems))}")
        checksums = download_checksums(gh, args.source_repository, release, asset_prefix, operating_systems)
        log(f"Updating generated blocks in {formula}")
        render_formula(formula, args.source_repository, release, asset_prefix, metadata, checksums)

        if run(git, "-C", str(tap_directory), "diff", "--quiet", "--", f"Formula/{formula_name}.rb", check=False).returncode == 0:
            log(f"Formula {formula_name} already has version {release.version}; skipping")
            return 0

        run(git, "-C", str(tap_directory), "config", "user.name", "x52dev release bot")
        run(git, "-C", str(tap_directory), "config", "user.email", "release-bot@users.noreply.github.com")
        log(f"Committing Formula/{formula_name}.rb")
        run(git, "-C", str(tap_directory), "add", f"Formula/{formula_name}.rb")
        run(git, "-C", str(tap_directory), "commit", "-m", f"chore: update {formula_name} to {release.version}")
        log(f"Pushing tap branch {branch}")
        run(git, "-C", str(tap_directory), "push", "--set-upstream", "origin", branch)
        log(f"Creating pull request in {args.tap}")
        run(gh, "pr", "create", "--repo", args.tap, "--base", args.base, "--head", branch, "--title", f"chore: update {formula_name} to {release.version}", "--body", f"Automated update from {args.source_repository} release {release.tag}.")
        return 0
    except UpdateError as error:
        log(str(error))
        return 1


if __name__ == "__main__":
    sys.exit(main())
