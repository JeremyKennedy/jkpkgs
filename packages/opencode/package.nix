{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
  unzip,
  fzf,
  ripgrep,
  testers,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;
  platformMap = {
    x86_64-linux = {
      asset = "opencode-linux-x64.tar.gz";
      isZip = false;
    };
    aarch64-linux = {
      asset = "opencode-linux-arm64.tar.gz";
      isZip = false;
    };
    x86_64-darwin = {
      asset = "opencode-darwin-x64.zip";
      isZip = true;
    };
    aarch64-darwin = {
      asset = "opencode-darwin-arm64.zip";
      isZip = true;
    };
  };
  platform = stdenv.hostPlatform.system;
  platformInfo = platformMap.${platform} or (throw "Unsupported: ${platform}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "opencode";
  inherit version;

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${version}/${platformInfo.asset}";
    hash = hashes.${platform};
  };

  sourceRoot = ".";
  dontStrip = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs =
    [ makeWrapper ]
    ++ lib.optionals platformInfo.isZip [ unzip ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 opencode $out/bin/opencode
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/opencode \
      --prefix PATH : ${lib.makeBinPath [ fzf ripgrep ]}
  '';
  meta = {
    description = "OpenCode AI coding assistant";
    platforms = builtins.attrNames platformMap;
    mainProgram = "opencode";
  };

  # opencode is a bun executable that creates XDG base directories
  # (~/.local/share, ~/.cache, ~/.config, ~/.local/state) on startup.
  # The build sandbox's HOME=/homeless-shelter is unwritable, so point
  # every XDG base directory at /tmp for the smoke test.
  passthru.tests.version = testers.testVersion {
    package = finalAttrs.finalPackage;
    command = "HOME=/tmp XDG_DATA_HOME=/tmp XDG_CACHE_HOME=/tmp XDG_STATE_HOME=/tmp XDG_CONFIG_HOME=/tmp opencode --version";
  };
})
