{
  appimageTools,
  fetchurl,
  lib,
  makeDesktopItem,
  stdenv,
  symlinkJoin,
  writeShellScript,
}:

let
  version = "0.7.2";
  base = appimageTools.wrapType2 {
    pname = "paseo-desktop";
    inherit version;

    src = fetchurl {
      url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-x86_64.AppImage";
      hash = "sha256-VjUdZF3MY3/OR9P1gCVkesBG6otIj9eFjTAkKo22mxY=";
    };
  };
  desktopLauncher = writeShellScript "paseo-desktop-launcher" ''
    unset PI_CONFIG_FILES PI_CODING_AGENT_DIR
    exec ${base}/bin/paseo-desktop "$@"
  '';
  desktopItem = makeDesktopItem {
    name = "paseo-desktop";
    desktopName = "Paseo";
    genericName = "AI coding agents";
    comment = "Desktop client for self-hosted coding agents";
    exec = "${desktopLauncher} %U";
    icon = "Paseo";
    categories = [ "Development" ];
    startupNotify = true;
    terminal = false;
  };
in
assert stdenv.hostPlatform.system == "x86_64-linux";
symlinkJoin {
  name = "paseo-desktop-${version}";
  paths = [
    base
    desktopItem
  ];

  meta = {
    description = "Paseo desktop app (Electron wrapper)";
    homepage = "https://paseo.sh";
    license = lib.licenses.asl20;
    mainProgram = "paseo-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
