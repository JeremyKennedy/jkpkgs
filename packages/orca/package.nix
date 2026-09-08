{
  appimageTools,
  fetchurl,
  lib,
  makeWrapper,
  stdenv,
  symlinkJoin,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;
  platform = stdenv.hostPlatform.system;
  base = appimageTools.wrapType2 {
    pname = "orca";
    inherit version;

    src = fetchurl {
      url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux.AppImage";
      hash = hashes.${platform};
    };
  };
in
assert platform == "x86_64-linux";
symlinkJoin {
  name = "orca-${version}";
  paths = [ base ];
  nativeBuildInputs = [ makeWrapper ];

  postBuild = ''
    rm "$out/bin/orca"
    makeWrapper ${base}/bin/orca "$out/bin/orca" \
      --unset PI_CONFIG_FILES \
      --unset PI_CODING_AGENT_DIR
  '';

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
