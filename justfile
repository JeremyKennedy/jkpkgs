dev:
    @echo "jkpkgs is a package-only repo. Use 'just check' or 'just build'."

check:
    node packages/pi/patch-context-files.test.mjs
    nix flake check --all-systems --no-build
    bash scripts/build-packages.sh --checks

build +packages="":
    bash scripts/build-packages.sh {{packages}}

# Build the patched Capacitor Android app. The signing secret is optional here:
# without it the release build fails, so use `just android-debug` instead.
android:
    #!/usr/bin/env bash
    set -euo pipefail
    repo_root=$(git rev-parse --show-toplevel)
    build_dir=$(mktemp -d)
    trap 'rm -rf "$build_dir"' EXIT
    bash "$repo_root/scripts/prepare-android-tree.sh" "$build_dir"
    cd "$build_dir"
    export JKPKGS_SHA=$(git -C "$repo_root" rev-parse --short HEAD)
    export OPENCHAMBER_ANDROID_VERSION_CODE=$(git -C "$repo_root" rev-list --count HEAD)
    export OPENCHAMBER_ANDROID_VERSION_NAME=$(node -p "require('./package.json').version")-jk$JKPKGS_SHA
    if [[ -r /run/agenix/openchamber_android_signing ]]; then
      export OPENCHAMBER_ANDROID_SIGNING_FILE=/run/agenix/openchamber_android_signing
    fi
    nix develop "$repo_root#android" -c bash "$repo_root/scripts/build-android.sh" release
    cp packages/mobile/android/app/build/outputs/apk/release/app-release.apk "$repo_root/result-android.apk"
    echo "APK: $repo_root/result-android.apk"

android-debug:
    #!/usr/bin/env bash
    set -euo pipefail
    repo_root=$(git rev-parse --show-toplevel)
    build_dir=$(mktemp -d)
    trap 'rm -rf "$build_dir"' EXIT
    bash "$repo_root/scripts/prepare-android-tree.sh" "$build_dir"
    cd "$build_dir"
    export JKPKGS_SHA=$(git -C "$repo_root" rev-parse --short HEAD)
    export OPENCHAMBER_ANDROID_VERSION_CODE=$(git -C "$repo_root" rev-list --count HEAD)
    export OPENCHAMBER_ANDROID_VERSION_NAME=$(node -p "require('./package.json').version")-jk$JKPKGS_SHA-debug
    nix develop "$repo_root#android" -c bash "$repo_root/scripts/build-android.sh" debug
    cp packages/mobile/android/app/build/outputs/apk/debug/app-debug.apk "$repo_root/result-android-debug.apk"
    echo "APK: $repo_root/result-android-debug.apk"

android-install:
    adb install -r result-android.apk
