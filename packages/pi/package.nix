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

  npmDepsFetcherVersion = 2;

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec/pi
    cp -R node_modules package.json package-lock.json $out/libexec/pi/

    ${nodejs}/bin/node ${./patch-context-files.mjs} $out/libexec/pi/node_modules/@earendil-works/pi-coding-agent

    # Verify pi loads every AGENTS.md/CLAUDE.md it finds while walking from
    # filesystem root to cwd. In particular, an AGENTS.md in a project must not
    # shadow ~/dev/CLAUDE.md or that project's own CLAUDE.md.
    context_test_dir=$(mktemp -d)
    export context_test_dir
    mkdir -p "$context_test_dir/agent" "$context_test_dir/home/dev/project"
    printf 'global agents' > "$context_test_dir/agent/AGENTS.md"
    printf 'global claude' > "$context_test_dir/agent/CLAUDE.md"
    printf 'root claude' > "$context_test_dir/CLAUDE.md"
    printf 'home claude' > "$context_test_dir/home/CLAUDE.md"
    printf 'dev claude' > "$context_test_dir/home/dev/CLAUDE.md"
    printf 'project agents' > "$context_test_dir/home/dev/project/AGENTS.md"
    printf 'project claude' > "$context_test_dir/home/dev/project/CLAUDE.md"
    ${nodejs}/bin/node --input-type=module <<EOF
    import { loadProjectContextFiles } from "$out/libexec/pi/node_modules/@earendil-works/pi-coding-agent/dist/core/resource-loader.js";
    const root = process.env.context_test_dir;
    const files = loadProjectContextFiles({
      cwd: root + "/home/dev/project",
      agentDir: root + "/agent",
    }).map((file) => file.path.slice(root.length));
    const expected = [
      "/agent/AGENTS.md",
      "/agent/CLAUDE.md",
      "/CLAUDE.md",
      "/home/CLAUDE.md",
      "/home/dev/CLAUDE.md",
      "/home/dev/project/AGENTS.md",
      "/home/dev/project/CLAUDE.md",
    ];
    if (JSON.stringify(files) !== JSON.stringify(expected)) {
      console.error("context file order mismatch");
      console.error("got", JSON.stringify(files));
      console.error("expected", JSON.stringify(expected));
      process.exit(1);
    }
    EOF

    # Ghostty supports Kitty keyboard protocol, but does not currently answer
    # pi-tui's protocol query. Enable it directly for pi sessions so modified
    # Backspace keys are distinguishable without global terminal key remaps.
    substituteInPlace $out/libexec/pi/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui/dist/terminal.js \
      --replace-fail 'process.stdout.write(KITTY_KEYBOARD_PROTOCOL_QUERY);' 'if (process.env.TERM_PROGRAM === "ghostty") { this._kittyProtocolActive = true; setKittyProtocolActive(true); this.keyboardProtocolNegotiationPending = false; this.keyboardProtocolLateResponsePending = false; this.clearKeyboardProtocolNegotiationBuffer(); process.stdout.write("\x1b[>7u"); return; } process.stdout.write(KITTY_KEYBOARD_PROTOCOL_QUERY);'

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
