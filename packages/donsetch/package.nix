{
  lib,
  pkgs,
  stdenv,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;
  platformMap = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
  };
  platform = stdenv.hostPlatform.system;
  asset = platformMap.${platform} or (throw "Unsupported: ${platform}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "donsetch";
  inherit version;

  src = fetchurl {
    url = "https://github.com/dondai44423/donsetch/releases/download/v${version}/donsetch-${asset}.tar.gz";
    hash = hashes.${platform};
  };

  # The archive is two root files (the binary and its optional ONNX runtime),
  # so unpackPhase has no directory to detect and must stay in the build dir.
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/donsetch $out/bin
    install -Dm755 donsetch $out/libexec/donsetch/donsetch
    install -Dm644 libonnxruntime.so $out/libexec/donsetch/libonnxruntime.so
    ln -s $out/libexec/donsetch/donsetch $out/bin/donsetch
    runHook postInstall
  '';

  # The binary dlopens libonnxruntime.so by bare name when a search needs
  # embeddings; RPATH alone would not find a library it never declares in
  # DT_NEEDED, so put its own directory on the loader path.
  postFixup = ''
    wrapProgram $out/bin/donsetch \
      --prefix LD_LIBRARY_PATH : $out/libexec/donsetch
  '';

  meta = {
    description = "Web search, fetch, crawl and screenshot tools for AI agents";
    homepage = "https://github.com/dondai44423/donsetch";
    license = lib.licenses.agpl3Plus;
    mainProgram = "donsetch";
    platforms = builtins.attrNames platformMap;
  };

  # Upstream has no network-free self-test; --version is the banner and exits
  # zero. Search needs the network, so it is not asserted here.
  passthru.tests.version = pkgs.runCommand "donsetch-version" { } ''
    ${finalAttrs.finalPackage}/bin/donsetch --version | grep -F "${finalAttrs.version}" > /dev/null
    touch $out
  '';
})
