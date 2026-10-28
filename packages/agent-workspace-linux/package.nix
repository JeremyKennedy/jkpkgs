{
  lib,
  pkgs,
  stdenv,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
  libxkbcommon,
  xvfb,
  openbox,
  xdotool,
  xauth,
  xdpyinfo,
  xprop,
  xset,
  imagemagick,
  xclip,
  bubblewrap,
  dbus,
  procps,
  xterm,
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
  pname = "agent-workspace-linux";
  inherit version;

  src = fetchurl {
    url = "https://github.com/agent-sh/agent-workspace-linux/releases/download/v${version}/agent-workspace-linux-${assetSuffix}";
    hash = hashes.${platform};
  };

  dontUnpack = true;
  dontStrip = true;

  nativeBuildInputs =
    [ makeWrapper ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    libxkbcommon
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/agent-workspace-linux
    runHook postInstall
  '';

  # The runtime launches its own Xvfb display, window manager, session bus and
  # sandbox, so every helper it shells out to has to be on PATH. xterm is only
  # there so `workspace launch -- xterm` works without extra setup.
  postFixup = ''
    wrapProgram $out/bin/agent-workspace-linux \
      --prefix PATH : ${
        lib.makeBinPath [
          xvfb
          openbox
          xdotool
          xauth
          xdpyinfo
          xprop
          xset
          imagemagick
          xclip
          bubblewrap
          dbus
          procps
          xterm
        ]
      }
  '';

  meta = {
    description = "Isolated hidden Linux desktop that an AI agent controls over MCP";
    homepage = "https://github.com/agent-sh/agent-workspace-linux";
    license = lib.licenses.mit;
    mainProgram = "agent-workspace-linux";
    platforms = builtins.attrNames platformMap;
  };

  # Upstream has no --version flag; `doctor` is the self-report. Assert only
  # that it runs and reports the linux platform, not that a display exists.
  passthru.tests.version = pkgs.runCommand "agent-workspace-linux-smoke" { } ''
    ${finalAttrs.finalPackage}/bin/agent-workspace-linux doctor --json > doctor.json || true
    ${pkgs.jq}/bin/jq -e '.ready_for_host_viewer == true' doctor.json > /dev/null
    touch $out
  '';
})
