#!/usr/bin/env bash
# Assert that the built mobile bundle carries every client-visible patch from
# the jkpkgs OpenChamber queue.
#
# The source the build starts from is already the applyPatches output, so a
# patch that does not apply fails `nix build` earlier. This check covers the
# step after that: that the bundle Capacitor packages is the one built from
# that tree, not a stale dist. It is per-patch on purpose: a single marker
# (the old `status-question` grep) went vacuous whenever upstream absorbed a
# patch, and proved nothing about the rest of the queue.
#
# markers.json classifies every patch as client (marker must be in the dist),
# server (the APK does not ship server code) or logic (no observable string).
# An unclassified patch fails the build, so a new patch cannot skip the check.
#
# Usage: assert-patch-markers.sh <dist-dir>
set -euo pipefail

dist="${1:?usage: assert-patch-markers.sh <dist-dir>}"
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
patches_dir="$script_dir/../packages/openchamber/patches"
markers="$patches_dir/markers.json"

if [[ ! -d "$dist" ]]; then
  echo "error: no built dist at $dist" >&2
  exit 1
fi
if [[ ! -f "$markers" ]]; then
  echo "error: no marker manifest at $markers" >&2
  exit 1
fi

# Coverage and shape of the manifest. Fails when a patch in the queue has no
# entry, when an entry names a patch that no longer exists, or when a client
# entry has no marker.
node - "$markers" "$patches_dir" <<'EOF'
const fs = require('fs');
const [markersPath, patchesDir] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(markersPath, 'utf8'));
const entries = manifest.patches;
const listed = new Map(entries.map((entry) => [entry.patch, entry]));
const actual = fs.readdirSync(patchesDir).filter((name) => name.endsWith('.patch'));
const missing = actual.filter((name) => !listed.has(name));
const stale = [...listed.keys()].filter((name) => !actual.includes(name));
let failed = false;
if (missing.length) {
  console.error(`error: patches missing from markers.json: ${missing.join(', ')}`);
  failed = true;
}
if (stale.length) {
  console.error(`error: markers.json lists patches that do not exist: ${stale.join(', ')}`);
  failed = true;
}
for (const entry of entries) {
  if (!['client', 'server', 'logic'].includes(entry.scope)) {
    console.error(`error: ${entry.patch} has an invalid scope: ${entry.scope}`);
    failed = true;
  }
  if (entry.scope === 'client' && !entry.marker) {
    console.error(`error: ${entry.patch} is client scope but has no marker`);
    failed = true;
  }
}
if (failed) process.exit(1);
EOF

failed=0
while IFS=$'\t' read -r patch marker; do
  if ! grep -RqF -- "$marker" "$dist"; then
    echo "error: marker for $patch ('$marker') is absent from $dist" >&2
    failed=1
  fi
done < <(node -e '
const manifest = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
for (const entry of manifest.patches) {
  if (entry.scope === "client") process.stdout.write(`${entry.patch}\t${entry.marker}\n`);
}
' "$markers")

if [[ "$failed" -ne 0 ]]; then
  echo "error: the mobile bundle is missing at least one client-visible patch" >&2
  exit 1
fi

echo "patch markers: ok"
