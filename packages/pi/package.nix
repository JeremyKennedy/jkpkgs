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

    # Ghostty supports Kitty keyboard protocol, but does not currently answer
    # pi-tui's protocol query. Enable it directly for pi sessions so modified
    # Backspace keys are distinguishable without global terminal key remaps.
    substituteInPlace $out/libexec/pi/node_modules/@earendil-works/pi-tui/dist/terminal.js \
      --replace-fail 'process.stdout.write("\x1b[?u");' 'if (process.env.TERM_PROGRAM === "ghostty") { this._kittyProtocolActive = true; setKittyProtocolActive(true); process.stdout.write("\x1b[>7u"); return; } process.stdout.write("\x1b[?u");'

    makeWrapper ${nodejs}/bin/node $out/bin/pi \
      --add-flags $out/libexec/pi/node_modules/@earendil-works/pi-coding-agent/dist/cli.js \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          nodejs
          openssh
        ]
      } \
      --set PI_SKIP_VERSION_CHECK 1 \
      --set PI_TELEMETRY 0 \
      --unset OPENAI_API_KEY \
      --unset OPENAI_BASE_URL \
      --unset OPENAI_ORG_ID \
      --unset OPENAI_PROJECT \
      --run 'export PI_CONFIG_DIR="''${PI_CONFIG_DIR:-$HOME/.pi}"'

    runHook postInstall
  '';

  meta = {
    description = "Pi Coding Agent CLI";
    homepage = "https://pi.dev";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
}
