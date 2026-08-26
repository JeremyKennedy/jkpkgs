{
  lib,
  stdenv,
  fetchurl,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;
  assetMap = {
    aarch64-darwin = "herdr-macos-aarch64";
    aarch64-linux = "herdr-linux-aarch64";
    x86_64-darwin = "herdr-macos-x86_64";
    x86_64-linux = "herdr-linux-x86_64";
  };
  platform = stdenv.hostPlatform.system;
  asset = assetMap.${platform} or (throw "herdr: unsupported system ${platform}");
in
stdenv.mkDerivation {
  pname = "herdr";
  inherit version;

  src = fetchurl {
    url = "https://github.com/herdrdev/herdr/releases/download/v${version}/${asset}";
    hash = hashes.${platform};
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';

  meta = {
    description = "Agent multiplexer that lives in your terminal";
    homepage = "https://herdr.dev";
    changelog = "https://github.com/herdrdev/herdr/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "herdr";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames assetMap;
  };
}
