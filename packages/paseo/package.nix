{
  lib,
  bash,
  buildNpmPackage,
  coreutils,
  findutils,
  git,
  gnugrep,
  gnused,
  makeWrapper,
  nodejs,
  openssh,
  procps,
  testers,
  which,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version npmDepsHash;

  package = buildNpmPackage {
    pname = "paseo";
    inherit version npmDepsHash;

    src = ./.;

    npmDepsFetcherVersion = 2;

    dontNpmBuild = true;

    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/libexec/paseo
      cp -R node_modules package.json package-lock.json $out/libexec/paseo/

      # Use the published launcher so the CLI keeps its own entrypoint and
      # warning flags while Node remains the wrapped runtime.
      makeWrapper ${nodejs}/bin/node $out/bin/paseo \
        --add-flags "--disable-warning=DEP0040" \
        --add-flags $out/libexec/paseo/node_modules/@getpaseo/cli/bin/paseo \
        --unset PI_CONFIG_FILES \
        --unset PI_CODING_AGENT_DIR \
        --prefix PATH : ${
          lib.makeBinPath [
            bash
            coreutils
            findutils
            git
            gnugrep
            gnused
            nodejs
            openssh
            procps
            which
          ]
        }

      runHook postInstall
    '';

    meta = {
      description = "Paseo daemon and desktop app backend CLI";
      homepage = "https://paseo.sh";
      mainProgram = "paseo";
    };
  };
in
package.overrideAttrs (
  finalAttrs: previousAttrs: {
    passthru = (previousAttrs.passthru or { }) // {
      tests.version = testers.testVersion {
        package = finalAttrs.finalPackage;
      };

      tests.help = testers.runCommand {
        name = "paseo-help-test";
        nativeBuildInputs = [ finalAttrs.finalPackage ];
        script = ''
          paseo --help >/dev/null
          touch "$out"
        '';
      };

      tests.daemonForeground = testers.runCommand {
        name = "paseo-daemon-foreground-test";
        nativeBuildInputs = [
          finalAttrs.finalPackage
          coreutils
          gnugrep
        ];
        script = ''
          export PASEO_HOME="$(mktemp -d)"
          export PASEO_LISTEN="127.0.0.1:0"
          export PASEO_RELAY_ENABLED="false"
          export PASEO_WEB_UI_ENABLED="false"

          daemon_pid=
          cleanup() {
            if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
              paseo daemon stop --home "$PASEO_HOME" --force >/dev/null 2>&1 || true
              kill "$daemon_pid" 2>/dev/null || true
              wait "$daemon_pid" 2>/dev/null || true
            fi
            rm -rf "$PASEO_HOME"
          }
          trap cleanup EXIT

          paseo daemon start --foreground >"$PASEO_HOME/stdout.log" 2>&1 &
          daemon_pid=$!

          for _ in $(seq 1 30); do
            if grep -q '"msg":"Worker ready"' "$PASEO_HOME/daemon.log" 2>/dev/null; then
              break
            fi
            if ! kill -0 "$daemon_pid" 2>/dev/null; then
              cat "$PASEO_HOME/stdout.log"
              cat "$PASEO_HOME/daemon.log" 2>/dev/null || true
              exit 1
            fi
            sleep 1
          done
          grep -q '"msg":"Worker ready"' "$PASEO_HOME/daemon.log"

          paseo daemon stop --home "$PASEO_HOME" >/dev/null
          wait "$daemon_pid"
          touch "$out"
        '';
      };
    };
  }
)
