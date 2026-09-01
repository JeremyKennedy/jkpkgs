{
  lib,
  stdenvNoCC,
  fetchurl,
  electron,
  p7zip,
  icoutils,
  asar,
  imagemagick,
  makeDesktopItem,
  makeWrapper,
  patchy-cnb,
  perl
}: let
  pname = "claude-desktop";
  version = "0.14.10";
  srcExe = fetchurl {
    # NOTE: `?v=${version}` doesn't actually request a specific version. It's only being used here as a cache buster.
    # This legacy path is retained only for non-Linux platforms until their native installers are migrated.
    url = "https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe?v=${version}";
    hash = "sha256-Sn/lvMlfKd7b/utFvCxrkWNDJTug4OOSA4lo9YV8aqk=";
  };
in
  stdenvNoCC.mkDerivation rec {
    inherit pname version;

    src = ./.;

    nativeBuildInputs = [
      p7zip
      asar
      makeWrapper
      imagemagick
      icoutils
      perl
    ];

    desktopItem = makeDesktopItem {
      name = "claude";
      exec = "claude-desktop %u";
      icon = "claude";
      type = "Application";
      terminal = false;
      desktopName = "Claude";
      genericName = "Claude Desktop";
      startupWMClass = "claude";
      categories = [
        "Office"
        "Utility"
      ];
      mimeTypes = [ "x-scheme-handler/claude" ];
    };

    buildPhase = ''
      runHook preBuild

      mkdir -p $TMPDIR/build
      cd $TMPDIR/build

      7z x -y ${srcExe}
      7z x -y "AnthropicClaude-${version}-full.nupkg"

      wrestool -x -t 14 lib/net45/claude.exe -o claude.ico
      icotool -x claude.ico

      for size in 16 24 32 48 64 256; do
        mkdir -p $TMPDIR/build/icons/hicolor/"$size"x"$size"/apps
        install -Dm 644 claude_*"$size"x"$size"x32.png \
          $TMPDIR/build/icons/hicolor/"$size"x"$size"/apps/claude.png
      done

      rm claude.ico

      mkdir -p electron-app
      cp "lib/net45/resources/app.asar" electron-app/
      cp -r "lib/net45/resources/app.asar.unpacked" electron-app/

      cd electron-app
      asar extract app.asar app.asar.contents
      SEARCH_BASE="app.asar.contents/.vite/renderer/main_window/assets"
      TARGET_PATTERN="MainWindowPage-*.js"
      TARGET_FILES=$(find "$SEARCH_BASE" -type f -name "$TARGET_PATTERN")
      NUM_FILES=$(echo "$TARGET_FILES" | grep -c .)
      if [ "$NUM_FILES" -ne 1 ]; then
        echo "Expected exactly one $TARGET_PATTERN, found $NUM_FILES" >&2
        exit 1
      fi
      TARGET_FILE="$TARGET_FILES"
      perl -i -pe 's{if\(!(\w+)\s*&&\s*(\w+)\)}{if($1 && $2)}g' "$TARGET_FILE"

      cp ${patchy-cnb}/lib/patchy-cnb.*.node app.asar.contents/node_modules/claude-native/claude-native-binding.node
      cp ${patchy-cnb}/lib/patchy-cnb.*.node app.asar.unpacked/node_modules/claude-native/claude-native-binding.node

      mkdir -p app.asar.contents/resources
      cp ../lib/net45/resources/Tray* app.asar.contents/resources/
      mkdir -p app.asar.contents/resources/i18n
      cp ../lib/net45/resources/*.json app.asar.contents/resources/i18n/
      asar pack app.asar.contents app.asar

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/$pname
      cp -r $TMPDIR/build/electron-app/app.asar $out/lib/$pname/
      cp -r $TMPDIR/build/electron-app/app.asar.unpacked $out/lib/$pname/

      mkdir -p $out/share/icons
      cp -r $TMPDIR/build/icons/* $out/share/icons

      mkdir -p $out/share/applications
      install -Dm0644 ${desktopItem}/share/applications/claude.desktop $out/share/applications/claude.desktop

      mkdir -p $out/bin
      makeWrapper ${electron}/bin/electron $out/bin/$pname \
        --add-flags "$out/lib/$pname/app.asar" \
        --add-flags "--openDevTools" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"

      runHook postInstall
    '';

    dontUnpack = true;
    dontConfigure = true;

    meta = with lib; {
      description = "Legacy Claude Desktop package for non-Linux platforms";
      platforms = platforms.unix;
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      mainProgram = pname;
    };

    passthru.tests = { };
  }
