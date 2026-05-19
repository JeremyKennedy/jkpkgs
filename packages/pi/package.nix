{
  lib,
  buildNpmPackage,
  git,
  makeWrapper,
  nodejs,
  openssh,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version npmDepsHash;
in
buildNpmPackage {
  pname = "pi";
  inherit version npmDepsHash;

  src = ./.;

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec/pi
    cp -R node_modules package.json package-lock.json $out/libexec/pi/

    makeWrapper ${nodejs}/bin/node $out/bin/pi \
      --add-flags $out/libexec/pi/node_modules/@earendil-works/pi-coding-agent/dist/cli.js \
      --prefix PATH : ${lib.makeBinPath [ git nodejs openssh ]} \
      --set PI_SKIP_VERSION_CHECK 1 \
      --set PI_TELEMETRY 0 \
      --run 'export PI_CODING_AGENT_DIR="''${PI_CODING_AGENT_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/pi/agent}"'

    runHook postInstall
  '';

  meta = {
    description = "Pi Coding Agent CLI";
    homepage = "https://pi.dev";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
}
