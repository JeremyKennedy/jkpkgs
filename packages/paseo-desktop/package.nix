{
  appimageTools,
  fetchurl,
  lib,
  stdenv,
}:

let
  version = "0.7.2";
in
assert stdenv.hostPlatform.system == "x86_64-linux";
appimageTools.wrapType2 {
  pname = "paseo-desktop";
  inherit version;

  src = fetchurl {
    url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-x86_64.AppImage";
    hash = "sha256-VjUdZF3MY3/OR9P1gCVkesBG6otIj9eFjTAkKo22mxY=";
  };

  meta = {
    description = "Paseo desktop app (Electron wrapper)";
    homepage = "https://paseo.sh";
    license = lib.licenses.asl20;
    mainProgram = "paseo-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
