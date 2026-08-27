{
  lib,
  stdenv,
  fetchzip,
  nodejs,
  testers,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "ccstatusline";
  inherit version;

  src = fetchzip {
    url = "https://registry.npmjs.org/ccstatusline/-/ccstatusline-${version}.tgz";
    hash = hashes.default;
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp dist/ccstatusline.js $out/bin/ccstatusline
    chmod +x $out/bin/ccstatusline
    substituteInPlace $out/bin/ccstatusline \
      --replace-quiet "#!/usr/bin/env node" "#!${nodejs}/bin/node"
    runHook postInstall
  '';
  meta = {
    description = "Status line formatter for Claude Code CLI";
    mainProgram = "ccstatusline";
  };

  passthru.tests.version = testers.testVersion {
    package = finalAttrs.finalPackage;
  };
})
