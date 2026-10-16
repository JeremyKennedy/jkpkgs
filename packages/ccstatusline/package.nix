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
    # 2.2.32 code-splits: the entry imports sibling chunks from dist/ by
    # relative path, so the whole tree ships next to it (2.2.30 was a
    # single bundle and copied the entry alone into bin/).
    mkdir -p $out/libexec/ccstatusline $out/bin
    cp -R dist/* $out/libexec/ccstatusline/
    mv $out/libexec/ccstatusline/ccstatusline.js $out/libexec/ccstatusline/ccstatusline
    chmod +x $out/libexec/ccstatusline/ccstatusline
    substituteInPlace $out/libexec/ccstatusline/ccstatusline \
      --replace-quiet "#!/usr/bin/env node" "#!${nodejs}/bin/node"
    ln -s $out/libexec/ccstatusline/ccstatusline $out/bin/ccstatusline
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
