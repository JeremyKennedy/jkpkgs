{
  lib,
  stdenv,
  autoPatchelfHook,
  bash,
  buildNpmPackage,
  coreutils,
  curl,
  findutils,
  git,
  gnugrep,
  gnused,
  makeWrapper,
  nodejs_24,
  openssh,
  procps,
  python3,
  ripgrep,
  testers,
  which,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version npmDepsHash;

  nodejs = nodejs_24;

  package = buildNpmPackage {
    pname = "openchamber";
    inherit version npmDepsHash nodejs;

    src = ./.;

    npmDepsFetcherVersion = 2;

    dontNpmBuild = true;

    nativeBuildInputs = [
      makeWrapper
      python3
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

    # The sherpa-onnx platform package (local dictation) ships prebuilt
    # onnxruntime/sherpa shared objects that link libstdc++ and libgcc_s.
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

    # node-pty's install script uses a bundled prebuild when one matches the
    # platform. This makes it delete every prebuild and compile pty.node
    # with node-gyp against the Nix node headers during `npm rebuild`.
    env.npm_config_build_from_source = "true";

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/libexec/openchamber
      cp -R node_modules package.json package-lock.json $out/libexec/openchamber/
      modules=$out/libexec/openchamber/node_modules

      # @vscode/ripgrep resolves rgPath to the binary in its platform package
      # (@vscode/ripgrep-<os>-<arch>/bin/rg). Point that at nixpkgs ripgrep
      # instead of a binary from the npm registry.
      for rg in $modules/@vscode/ripgrep-*/bin/rg; do
        ln -sf ${lib.getExe ripgrep} "$rg"
      done

      # Keep only the compiled pty.node (and darwin's spawn-helper). The gyp
      # Makefiles and config.gypi reference python3 and the node source tree,
      # which would otherwise land in the runtime closure; conpty is Windows-only.
      find $modules/node-pty/build -mindepth 1 -maxdepth 1 ! -name Release -exec rm -rf {} +
      find $modules/node-pty/build/Release -mindepth 1 -maxdepth 1 \
        ! -name pty.node ! -name spawn-helper -exec rm -rf {} +
      find $modules/node-pty/node-addon-api -name '*.mk' -delete
      rm -rf $modules/node-pty/third_party/conpty

      # bun-pty is only imported under the Bun runtime; under Node the server
      # always uses node-pty. Drop its prebuilt per-platform libraries.
      rm -rf $modules/bun-pty/rust-pty

      makeWrapper ${nodejs}/bin/node $out/bin/openchamber \
        --add-flags $modules/@openchamber/web/bin/cli.js \
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
            ripgrep
            which
          ]
        }

      runHook postInstall
    '';

    meta = {
      description = "Web interface for the OpenCode AI coding agent";
      homepage = "https://github.com/openchamber/openchamber";
      license = lib.licenses.mit;
      mainProgram = "openchamber";
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
        name = "openchamber-help-test";
        nativeBuildInputs = [ finalAttrs.finalPackage ];
        script = ''
          openchamber --help | grep -q -- '--foreground'
          touch "$out"
        '';
      };

      tests.serveForeground = testers.runCommand {
        name = "openchamber-serve-foreground-test";
        nativeBuildInputs = [
          finalAttrs.finalPackage
          coreutils
          curl
          gnugrep
        ];
        script = ''
          export HOME="$(mktemp -d)"
          export XDG_CONFIG_HOME="$HOME/.config"
          export XDG_DATA_HOME="$HOME/.local/share"
          export XDG_STATE_HOME="$HOME/.local/state"
          export XDG_CACHE_HOME="$HOME/.cache"
          export OPENCHAMBER_HOST=127.0.0.1
          export OPENCHAMBER_PORT=38917
          export OPENCODE_SKIP_START=true
          export OPENCODE_HOST=http://127.0.0.1:1

          # `serve` refuses to start without an opencode executable even when
          # it only connects to an external server; the service supplies the
          # real one, so a stub is enough to serve the UI here.
          printf '#!${bash}/bin/sh\nexit 0\n' >"$HOME/opencode"
          chmod +x "$HOME/opencode"
          export OPENCODE_BINARY="$HOME/opencode"

          server_pid=
          cleanup() {
            if [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; then
              kill "$server_pid" 2>/dev/null || true
              wait "$server_pid" 2>/dev/null || true
            fi
          }
          trap cleanup EXIT

          openchamber serve --foreground --port "$OPENCHAMBER_PORT" >"$HOME/server.log" 2>&1 &
          server_pid=$!

          status=
          for _ in $(seq 1 60); do
            status="$(curl -s -o "$HOME/index.html" -w '%{http_code}' "http://127.0.0.1:$OPENCHAMBER_PORT/" || true)"
            [ "$status" = 200 ] && break
            if ! kill -0 "$server_pid" 2>/dev/null; then
              cat "$HOME/server.log"
              exit 1
            fi
            sleep 1
          done
          if [ "$status" != 200 ]; then
            cat "$HOME/server.log"
            exit 1
          fi
          grep -qi '<html' "$HOME/index.html"
          touch "$out"
        '';
      };

      # The terminal backend under Node: the from-source pty.node must load
      # and spawn a process.
      tests.nodePty = testers.runCommand {
        name = "openchamber-node-pty-test";
        nativeBuildInputs = [ nodejs ];
        script = ''
          cd ${finalAttrs.finalPackage}/libexec/openchamber
          node -e '
            const pty = require("node-pty");
            const p = pty.spawn("${bash}/bin/bash", ["-c", "echo pty-ok"], {});
            let out = "";
            p.onData((d) => { out += d; });
            p.onExit(() => { process.exit(out.includes("pty-ok") ? 0 : 1); });
          '
          touch "$out"
        '';
      };
    };
  }
)
