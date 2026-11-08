#!/usr/bin/env bash
# Build the Capacitor Android app from the patched tree prepared by
# prepare-android-tree.sh. Run this inside `nix develop .#android`, from the
# prepared tree root.
#
# Usage: build-android.sh [release|debug]
set -euo pipefail

mode="${1:-release}"
case "$mode" in
  release | debug) ;;
  *)
    echo "usage: build-android.sh [release|debug]" >&2
    exit 1
    ;;
esac

: "${JAVA_HOME:?JAVA_HOME must be set (nix develop .#android)}"
: "${ANDROID_HOME:?ANDROID_HOME must be set (nix develop .#android)}"

if [[ -n "${OPENCHAMBER_ANDROID_SIGNING_FILE:-}" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$OPENCHAMBER_ANDROID_SIGNING_FILE"
  set +a
  : "${OPENCHAMBER_ANDROID_KEYSTORE_BASE64:?signing file lacks OPENCHAMBER_ANDROID_KEYSTORE_BASE64}"
  keystore_dir=$(mktemp -d)
  trap 'rm -rf "$keystore_dir"' EXIT
  printf '%s' "$OPENCHAMBER_ANDROID_KEYSTORE_BASE64" | base64 -d \
    >"$keystore_dir/openchamber-android.jks"
  export OPENCHAMBER_ANDROID_KEYSTORE_PATH="$keystore_dir/openchamber-android.jks"
fi

if [[ "$mode" == "release" ]]; then
  : "${OPENCHAMBER_ANDROID_KEYSTORE_PATH:?release builds need a signing keystore}"
  : "${OPENCHAMBER_ANDROID_KEYSTORE_PASSWORD:?release builds need a keystore password}"
  : "${OPENCHAMBER_ANDROID_KEY_ALIAS:?release builds need a key alias}"
  : "${OPENCHAMBER_ANDROID_KEY_PASSWORD:?release builds need a key password}"
fi

version="${OPENCHAMBER_ANDROID_VERSION_NAME:-$(node -p "require('./package.json').version")-local}"
code="${OPENCHAMBER_ANDROID_VERSION_CODE:-$(date +%s)}"
export OPENCHAMBER_ANDROID_VERSION_NAME="$version"
export OPENCHAMBER_ANDROID_VERSION_CODE="$code"

echo "OpenChamber Android $mode build: versionName=$version versionCode=$code"

# The server imports the SDK at runtime, and the web build resolves it through
# its dist entry. Build it before the mobile/web assets.
bun run --cwd packages/sdk build

# Web build + mobile assets + Capacitor sync. This is the same pipeline as a
# manual build; the only difference is the patched source it starts from.
bun run --cwd packages/mobile sync

# Belt-and-suspenders for the patch queue: applyPatches already fails when a
# patch does not apply, but the marker proves the patched UI reached the
# bundle that Capacitor packages into the APK.
if ! grep -Rq 'status-question' packages/mobile/dist; then
  echo "error: purple question patch is absent from packages/mobile/dist" >&2
  exit 1
fi

./packages/mobile/android/gradlew -p packages/mobile/android "assemble${mode^}"

apk="packages/mobile/android/app/build/outputs/apk/${mode}/app-${mode}.apk"
if [[ ! -f "$apk" ]]; then
  apk="packages/mobile/android/app/build/outputs/apk/${mode}/app-${mode}-unsigned.apk"
fi
if [[ ! -f "$apk" ]]; then
  echo "error: no APK under packages/mobile/android/app/build/outputs/apk/${mode}" >&2
  exit 1
fi

build_tools="$ANDROID_HOME/build-tools/35.0.0"
"$build_tools/apksigner" verify --print-certs "$apk"
"$build_tools/aapt" dump badging "$apk" | sed -n '1,5p'

printf '%s\n' "$apk"
