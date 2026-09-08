{
  appimageTools,
  fetchurl,
  lib,
  stdenv,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;
  platform = stdenv.hostPlatform.system;
in
assert platform == "x86_64-linux";
appimageTools.wrapType2 {
  pname = "orca";
  inherit version;

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
    hash = hashes.${platform};
  };

  meta = {
    description = "Agent development environment for parallel coding agents";
    homepage = "https://github.com/stablyai/orca";
    changelog = "https://github.com/stablyai/orca/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "orca";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
