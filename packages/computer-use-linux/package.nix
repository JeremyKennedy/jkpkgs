{
  lib,
  pkgs,
  stdenv,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
  hyprland,
  grim,
  wtype,
  ydotool,
  xdotool,
  at-spi2-core,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;
  platformMap = {
    x86_64-linux = "x86_64-unknown-linux-gnu";
    aarch64-linux = "aarch64-unknown-linux-gnu";
  };
  platform = stdenv.hostPlatform.system;
  assetSuffix = platformMap.${platform} or (throw "Unsupported: ${platform}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "computer-use-linux";
  inherit version;

  src = fetchurl {
    url = "https://github.com/agent-sh/computer-use-linux/releases/download/v${version}/computer-use-linux-${assetSuffix}";
    hash = hashes.${platform};
  };

  dontUnpack = true;
  dontStrip = true;

  nativeBuildInputs =
    [ makeWrapper ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/computer-use-linux
    runHook postInstall
  '';

  # The CLI shells out for compositor discovery and input: hyprctl on
  # Hyprland, grim/portal for capture, wtype for text, ydotool as the uinput
  # fallback, xdotool for X11 sessions, and the AT-SPI bus for semantic trees.
  postFixup = ''
    wrapProgram $out/bin/computer-use-linux \
      --prefix PATH : ${
        lib.makeBinPath [
          hyprland
          grim
          wtype
          ydotool
          xdotool
          at-spi2-core
        ]
      }
  '';

  meta = {
    description = "Native Linux desktop control for AI agents (MCP server and CLI)";
    homepage = "https://github.com/agent-sh/computer-use-linux";
    license = lib.licenses.mit;
    mainProgram = "computer-use-linux";
    platforms = builtins.attrNames platformMap;
  };

  # Upstream has no --version flag; `doctor --json` is the closest
  # self-report. It must run headless in the sandbox, so only the platform
  # fields are asserted, not session readiness.
  passthru.tests.version = pkgs.runCommand "computer-use-linux-smoke" { } ''
    ${finalAttrs.finalPackage}/bin/computer-use-linux doctor --json > doctor.json || true
    ${pkgs.jq}/bin/jq -e '.platform.os == "linux"' doctor.json > /dev/null
    touch $out
  '';
})
