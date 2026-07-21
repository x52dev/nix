# Format project.
fmt:
    nix fmt

# Check all flake outputs and release-tool fixtures.
check:
    nix flake check
