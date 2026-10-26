{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs,
  bash,
  coreutils,
  procps,
  testers,
}:
let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version npmDepsHash;

  package = buildNpmPackage {
    pname = "rea";
    inherit version npmDepsHash;

    src = ./.;

    npmDepsFetcherVersion = 2;

    dontNpmBuild = true;

    # frida's install script downloads a prebuilt toolchain from the
    # network; keep dependency installation offline. Frida-backed
    # commands are unavailable in this build, every static analysis is not.
    npmFlags = [ "--ignore-scripts" ];

    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/libexec/rea
      cp -R node_modules package.json package-lock.json $out/libexec/rea/

      # REA resolves its dist/, scripts/ and bridge/ trees relative to the
      # installed package, so run the published entry point in place.
      makeWrapper ${nodejs}/bin/node $out/bin/rea \
        --add-flags $out/libexec/rea/node_modules/rea-agents/scripts/rea.mjs \
        --prefix PATH : ${
          lib.makeBinPath [
            bash
            coreutils
            nodejs
            procps
          ]
        }

      runHook postInstall
    '';

    meta = {
      description = "Reverse engineer anything from your terminal or agent with one CLI and MCP server";
      homepage = "https://github.com/morluto/rea";
      license = lib.licenses.mit;
      mainProgram = "rea";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  };
in
package.overrideAttrs (finalAttrs: previousAttrs: {
  passthru = (previousAttrs.passthru or { }) // {
    tests.version = testers.testVersion {
      package = finalAttrs.finalPackage;
    };
  };
})
