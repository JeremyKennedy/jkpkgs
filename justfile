dev:
    @echo "jkpkgs is a package-only repo. Use 'just check' or 'just build'."

check:
    nix flake check

build:
    nix build .#claude-code .#opencode .#ccstatusline
