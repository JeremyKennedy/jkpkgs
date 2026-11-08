#!/usr/bin/env bash
# Publish the APK built by build-android.sh as a versioned Forgejo release.
# Run inside `nix develop .#android` so curl/node/git are available.
#
# Required env: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_NUMBER, BUILD_DIR
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_RUN_NUMBER:?GITHUB_RUN_NUMBER is required}"
: "${BUILD_DIR:?BUILD_DIR is required}"

repo_root=$(git rev-parse --show-toplevel)
version=$(node -p "require('$BUILD_DIR/package.json').version")
sha=$(git -C "$repo_root" rev-parse --short HEAD)
tag="openchamber-android-${version}-${sha}-${GITHUB_RUN_NUMBER}"
asset="OpenChamber-${version}-jk${sha}-android.apk"
apk="$BUILD_DIR/packages/mobile/android/app/build/outputs/apk/release/app-release.apk"

if [[ ! -f "$apk" ]]; then
  echo "error: missing $apk" >&2
  exit 1
fi

patches=$(cd "$repo_root" && printf '%s\n' packages/openchamber/patches/*.patch |
  sed 's|packages/openchamber/patches/||' | paste -sd ', ' -)

export VERSION="$version" SHA="$sha" TAG="$tag" PATCHES="$patches" ASSET="$asset"

payload=$(node -e '
const body = [
  `Patched Android build of OpenChamber ${process.env.VERSION}.`,
  ``,
  `Source: jkpkgs ${process.env.SHA}.`,
  `Patches: ${process.env.PATCHES}.`,
  ``,
  `First install: uninstall com.openchamber.app once (the upstream APK uses a`,
  `different signing key), then install this APK and pair the device again.`,
  `Later builds signed with the same key update in place.`,
].join("\n");
console.log(JSON.stringify({
  tag_name: process.env.TAG,
  target_commitish: process.env.GITHUB_SHA,
  name: `OpenChamber ${process.env.VERSION} (patched Android build ${process.env.GITHUB_RUN_NUMBER})`,
  body,
  draft: false,
  prerelease: false,
}));
')

api="https://git.jeremyk.net/api/v1/repos/${GITHUB_REPOSITORY}"
release=$(curl -fsS -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$payload" \
  "$api/releases")

release_id=$(printf '%s' "$release" | node -e '
let input = "";
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  const parsed = JSON.parse(input);
  if (!parsed.id) {
    console.error(input);
    process.exit(1);
  }
  process.stdout.write(String(parsed.id));
});
')

curl -fsS -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -F "attachment=@${apk}" \
  "$api/releases/${release_id}/assets?name=${asset}"

echo "published ${tag} (${asset})"
