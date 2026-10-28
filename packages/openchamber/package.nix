{
  lib,
  stdenv,
  bash,
  bzip2,
  callPackage,
  cloudflared,
  coreutils,
  curl,
  git,
  gnugrep,
  gnutar,
  less,
  makeWrapper,
  nodejs,
  openchamberSource,
  opencode,
  openssh,
  python3,
  testers,
}:

# The build mirrors upstream's nix/package.nix (itself their Docker recipe):
# a bun install of the whole workspace, the sdk and web builds, and a bun
# runtime over that tree. jkpkgs owns the recipe rather than importing
# upstream's because the dependency step differs (see bunDeps) and because
# importing a recipe out of the patched tree would make evaluation depend
# on building it.
let
  source = callPackage ./source.nix { inherit openchamberSource; };
  inherit (source) bun version src;

  # Runtime PATH parity with upstream's Docker image. The OpenCode CLI is
  # jkpkgs' own; the dotfiles instances attach to the managed OpenCode
  # server and name its binary explicitly.
  runtimePath = lib.makeBinPath [
    bun
    nodejs
    git
    openssh
    python3
    cloudflared
    less
    bash
    coreutils
    # tar + bzip2 unpack the local dictation model.
    gnutar
    bzip2
    opencode
  ];

  # The whole workspace dependency tree, fixed-output. Upstream installs
  # only the host platform's optional dependencies and bakes a hash per
  # host; installing every platform's makes the tree identical on Linux and
  # Darwin, so one hash in hashes.json covers both. The core prunes it back
  # to the host.
  bunDeps = stdenv.mkDerivation {
    pname = "openchamber-bun-deps";
    inherit version src;

    nativeBuildInputs = [ bun ];

    dontConfigure = true;
    buildPhase = ''
      export HOME="$PWD/.bun-home"
      mkdir -p "$HOME"
      bun install --frozen-lockfile --ignore-scripts --os='*' --cpu='*'
    '';
    installPhase = ''
      mkdir -p "$out"
      cp -a node_modules "$out/node_modules"
      find packages -maxdepth 2 -type d -name node_modules | while read -r dir; do
        mkdir -p "$out/$(dirname "$dir")"
        cp -a "$dir" "$out/$dir"
      done
      # bun links dependency bins inside store entries inconsistently across
      # platforms (one browserslist link exists on Linux only), which breaks
      # the shared hash. Nothing resolves them: builds use the workspace
      # .bin directories, which stay.
      find "$out/node_modules/.bun" -mindepth 3 -maxdepth 3 -type d -name .bin \
        -path '*/node_modules/.bin' -exec rm -rf {} +
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = source.bunDeps;

    # Byte-identical to what bun produced: workspace .bin symlinks only
    # resolve once this is overlaid on the source tree.
    dontFixup = true;
  };

  # Deps + sdk/web build + the runtime layout both the server and the
  # desktop app consume (upstream's openchamberCore).
  core = stdenv.mkDerivation {
    pname = "openchamber-core";
    inherit version src;

    nativeBuildInputs = [
      bun
      nodejs
    ];

    configurePhase = ''
      cp -a "${bunDeps}"/. .
      chmod -R u+w .
      bun ${./prune-foreign-platforms.mjs} .
      # The sandbox has no /usr/bin/env.
      patchShebangs node_modules
      for dir in packages/*/node_modules; do
        [ -d "$dir" ] && patchShebangs "$dir"
      done
    '';

    buildPhase = ''
      # The server imports @openchamber/sdk at runtime, so its dist must exist.
      bun run --cwd packages/sdk build
      bun run build:web
    '';

    installPhase = ''
      appRoot="$out/lib/openchamber"
      mkdir -p "$appRoot/packages/web" "$appRoot/packages/sdk"
      cp package.json "$appRoot/package.json"
      cp -a node_modules "$appRoot/node_modules"
      if [ -d packages/web/node_modules ]; then
        cp -a packages/web/node_modules "$appRoot/packages/web/node_modules"
      fi
      cp packages/web/package.json "$appRoot/packages/web/package.json"
      cp -a packages/web/bin "$appRoot/packages/web/bin"
      cp -a packages/web/server "$appRoot/packages/web/server"
      cp -a packages/web/dist "$appRoot/packages/web/dist"
      cp packages/sdk/package.json "$appRoot/packages/sdk/package.json"
      cp -a packages/sdk/dist "$appRoot/packages/sdk/dist"
    '';

    passthru = {
      inherit bunDeps src;
    };

    # node_modules must stay as bun laid it out.
    dontFixup = true;
  };

  package = stdenv.mkDerivation {
    pname = "openchamber";
    inherit version;

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      mkdir -p "$out/bin"
      makeWrapper "${bun}/bin/bun" "$out/bin/openchamber" \
        --run "cd ${core}/lib/openchamber" \
        --add-flags "packages/web/bin/cli.js" \
        --prefix PATH : "${runtimePath}" \
        --set NODE_ENV production \
        --set LANG C.UTF-8
    '';

    passthru = {
      inherit bunDeps core source;
    };

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
    passthru = previousAttrs.passthru // {

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

      # The terminal backend under bun: the server imports bun-pty from the
      # runtime tree, and its prebuilt library must load and spawn a process.
      tests.bunPty = testers.runCommand {
        name = "openchamber-bun-pty-test";
        nativeBuildInputs = [ source.bun ];
        script = ''
          cd ${finalAttrs.finalPackage.passthru.core}/lib/openchamber/packages/web
          bun -e '
            const { spawn } = await import("bun-pty");
            const p = spawn("${bash}/bin/bash", ["-c", "echo pty-ok"], {});
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
