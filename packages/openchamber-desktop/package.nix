{
  appimageTools,
  fetchurl,
  lib,
  stdenv,
}:
let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;
  pname = "openchamber-desktop";
  src = fetchurl {
    url = "https://github.com/openchamber/openchamber/releases/download/v${version}/OpenChamber-${version}-linux-x86_64.AppImage";
    hash = hashes.${stdenv.hostPlatform.system};
  };
  contents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  extraInstallCommands = ''
    install -Dm644 ${contents}/openchamber.desktop $out/share/applications/openchamber.desktop
    substituteInPlace $out/share/applications/openchamber.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=openchamber-desktop'
    cp -r ${contents}/usr/share/icons $out/share/
  '';
  # GUI application: no CLI --version smoke test (it launches Electron).
  meta = {
    description = "OpenChamber desktop interface for OpenCode";
    homepage = "https://openchamber.dev";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
