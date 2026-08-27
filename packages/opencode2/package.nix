{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  patchelf,
  fzf,
  ripgrep,
  testers,
}:
let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;
  # OpenCode 2 beta ships via npm platform packages
  # (@opencode-ai/cli-<platform>-<arch>); the @opencode-ai/cli wrapper's
  # postinstall merely copies bin/opencode2 out of the platform package.
  # We fetch the platform tarball directly — no postinstall, no npm at
  # build time. Beta versions churn; update hashes.json per beta tag.
  platformMap = {
    x86_64-linux = "cli-linux-x64";
    aarch64-linux = "cli-linux-arm64";
    aarch64-darwin = "cli-darwin-arm64";
    x86_64-darwin = "cli-darwin-x64";
  };
  platform = stdenv.hostPlatform.system;
  platformPkg = platformMap.${platform} or (throw "opencode2: unsupported system ${platform}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "opencode2";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode-ai/${platformPkg}/-/${platformPkg}-${version}.tgz";
    hash = hashes.${platform};
  };
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  # The bun executable's interpreter is the host nix-ld loader
  # (/lib64/ld-linux-x86-64.so.2). That path does not exist inside the
  # build sandbox or on non-NixOS Linux, so rewrite it to the store
  # glibc loader. Only --set-interpreter: bun standalone executables
  # carry an appended trailer located by baked-in byte offsets, and any
  # patchelf operation that resizes the ELF shifts those offsets and
  # corrupts it (see packages/oh-my-pi for the full analysis).
  postPatch = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} package/bin/opencode2
  '';

  nativeBuildInputs = [
    makeWrapper
    patchelf
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 package/bin/opencode2 $out/bin/opencode2
    runHook postInstall
  '';
  postFixup = ''
    wrapProgram $out/bin/opencode2 \
      --prefix PATH : ${
        lib.makeBinPath [
          fzf
          ripgrep
        ]
      }
  '';

  meta = {
    description = "OpenCode 2 beta AI coding assistant";
    homepage = "https://opencode.ai/v2/docs";
    platforms = builtins.attrNames platformMap;
    mainProgram = "opencode2";
  };
  # Like opencode, opencode2 is a bun executable that creates XDG base
  # directories on startup; the sandbox HOME is unwritable, so redirect
  # them to /tmp. The ELF interpreter is rewritten in postPatch, so the
  # wrapper runs as-is inside the build sandbox.
  # `opencode2 --version` prints "opencode2 v<version>" and the bare
  # version is not a standalone word there (the "v" glues onto it for
  # grep -w), so match the prefixed form.
  passthru.tests.version = testers.testVersion {
    package = finalAttrs.finalPackage;
    command = "HOME=/tmp XDG_DATA_HOME=/tmp XDG_CACHE_HOME=/tmp XDG_STATE_HOME=/tmp XDG_CONFIG_HOME=/tmp opencode2 --version";
    version = "v${version}";
  };
})
