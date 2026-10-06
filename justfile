dev:
    @echo "jkpkgs is a package-only repo. Use 'just check' or 'just build'."

check:
    node packages/pi/patch-context-files.test.mjs
    nix flake check --all-systems --no-build
    bash scripts/build-packages.sh --checks

build +packages="":
    bash scripts/build-packages.sh {{packages}}
