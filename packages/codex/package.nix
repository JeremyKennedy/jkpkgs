{
  stdenv,
  fetchzip,
  nodejs,
  makeWrapper,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;
  platformMap = {
    x86_64-linux = {
      assetSuffix = "linux-x64";
      vendorPath = "vendor/x86_64-unknown-linux-musl";
    };
    aarch64-linux = {
      assetSuffix = "linux-arm64";
      vendorPath = "vendor/aarch64-unknown-linux-musl";
    };
    x86_64-darwin = {
      assetSuffix = "darwin-x64";
      vendorPath = "vendor/x86_64-apple-darwin";
    };
    aarch64-darwin = {
      assetSuffix = "darwin-arm64";
      vendorPath = "vendor/aarch64-apple-darwin";
    };
  };
  platform = stdenv.hostPlatform.system;
  platformInfo = platformMap.${platform} or (throw "Unsupported codex platform: ${platform}");
in
stdenv.mkDerivation {
  pname = "codex";
  inherit version;

  src = fetchzip {
    url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}-${platformInfo.assetSuffix}.tgz";
    hash = hashes.${platform};
  };

  nativeBuildInputs = [ makeWrapper ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec/codex
    cp -R ${platformInfo.vendorPath} $out/libexec/codex/vendor
    cp package.json README.md $out/libexec/codex/
    makeWrapper $out/libexec/codex/vendor/codex/codex $out/bin/codex \
      --prefix PATH : $out/libexec/codex/vendor/path \
      --set CODEX_MANAGED_NODE_PATH ${nodejs}/bin/node \
      --set CODEX_MANAGED_VENDOR_DIR $out/libexec/codex/vendor
    ln -s $out/bin/codex $out/bin/co
    runHook postInstall
  '';

  meta = {
    description = "OpenAI Codex CLI";
    mainProgram = "codex";
    platforms = builtins.attrNames platformMap;
  };
}
