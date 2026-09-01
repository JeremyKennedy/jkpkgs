{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs,
  bash,
  git,
  openssh,
  fd,
  ripgrep,
  testers,
}:
let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version npmDepsHash;
  package = buildNpmPackage {
    pname = "dsh";
    inherit version npmDepsHash;
    src = ./.;
    npmDepsFetcherVersion = 2;
    dontNpmBuild = true;
    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/libexec/dsh
      cp -R node_modules package.json package-lock.json $out/libexec/dsh/
      ${nodejs}/bin/node \
        $out/libexec/dsh/node_modules/@deepseek-ai/dsh-subprocess-local/scripts/ensure-spawn-helper.mjs
      makeWrapper ${nodejs}/bin/node $out/bin/dsh \
        --add-flags $out/libexec/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js \
        --prefix PATH : ${lib.makeBinPath [ bash git openssh fd ripgrep nodejs ]}
      runHook postInstall
    '';

    meta = {
      description = "DeepSeek Harness agent CLI";
      homepage = "https://github.com/deepseek-ai/deepseek-harness";
      license = lib.licenses.mit;
      mainProgram = "dsh";
      platforms = [ "x86_64-linux" "aarch64-darwin" ];
    };
  };
in
package.overrideAttrs (finalAttrs: previousAttrs: {
  passthru = (previousAttrs.passthru or { }) // {
    tests.version = testers.testVersion {
      package = finalAttrs.finalPackage;
    };
    tests.nativeTerminal = testers.runCommand {
      name = "dsh-native-terminal-test";
      nativeBuildInputs = [ finalAttrs.finalPackage nodejs ];
      script = ''
        dsh --help >/dev/null
        cd ${finalAttrs.finalPackage}/libexec/dsh
        ${nodejs}/bin/node --input-type=module <<'EOF'
        import { accessSync, constants, existsSync } from "node:fs";
        import { resolve } from "node:path";
        await import("node-pty");
        await import("koffi");
        for (const platform of ["darwin-arm64", "darwin-x64", "linux-arm64", "linux-x64"]) {
          const helper = resolve("node_modules/node-pty/prebuilds", platform, "spawn-helper");
          if (existsSync(helper)) accessSync(helper, constants.X_OK);
        }
        EOF
        touch $out
      '';
    };
  };
})
