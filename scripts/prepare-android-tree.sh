#!/usr/bin/env bash
# Materialize the jkpkgs-patched OpenChamber source plus its bun dependency
# tree into a writable directory. The Android build needs both: the source
# carries every local patch, and bunDeps is the fixed-output install that the
# web/desktop packages already use.
#
# Usage: prepare-android-tree.sh <outdir>
set -euo pipefail

out="${1:?usage: prepare-android-tree.sh <outdir>}"
repo_root=$(git rev-parse --show-toplevel)

mkdir -p "$out"

src=$(nix build --no-link --print-out-paths "$repo_root#openchamber.passthru.source.src")
deps=$(nix build --no-link --print-out-paths "$repo_root#openchamber.passthru.bunDeps")

cp -a "$src"/. "$out/"
chmod -R u+w "$out"
cp -a "$deps"/. "$out/"
chmod -R u+w "$out"

printf '%s\n' "$out"
