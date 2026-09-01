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
        --add-flags "--expose-internals" \
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
    tests.webStartup = testers.runCommand {
      name = "dsh-web-startup-test";
      nativeBuildInputs = [ finalAttrs.finalPackage ];
      script = ''
        export DSH_HOME="$(mktemp -d)"
        trap 'if [ -n "''${server_pid:-}" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi; rm -rf "$DSH_HOME"' EXIT

        dsh web --no-open >"$DSH_HOME/web.log" 2>&1 &
        server_pid=$!
        for _ in $(seq 1 30); do
          if grep -q '^dsh web: http://127\.0\.0\.1:' "$DSH_HOME/web.log"; then
            break
          fi
          if ! kill -0 "$server_pid" 2>/dev/null; then
            cat "$DSH_HOME/web.log"
            exit 1
          fi
          sleep 1
        done
        grep -q '^dsh web: http://127\.0\.0\.1:' "$DSH_HOME/web.log"
        kill "$server_pid"
        wait "$server_pid" || test "$?" -eq 143
        touch "$out"
      '';
    };
  };
})
