{
  lib,
  stdenvNoCC,
  nodejs,
  fzf,
  drovrSource,
}:

let
  manifest = lib.importTOML "${drovrSource}/herdr-plugin.toml";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "herdr-drovr";
  version = manifest.version;

  # The install-check suite filters candidate lists through the real fzf.
  nativeBuildInputs = [ nodejs fzf ];

  src = drovrSource;

  # Upstream's pane picker defaults to the current workspace's tabs, which
  # reads as an empty picker from a single-tab workspace. Default the list to
  # cross-workspace and repurpose ctrl-t to narrow to the current space.
  # Drift fails closed at build time; regenerate against the pinned input:
  #   git diff upstream/main -- pick-and-move.ts > patches/all-spaces-default.patch
  patches = [ ./patches/all-spaces-default.patch ];

  # No build step: herdr runs the TypeScript sources through node's native
  # type stripping. Install is a copy of the manifest plus the entrypoints.
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r herdr-plugin.toml compile-cache.js open-picker.ts pick-and-move.ts LICENSE README.md $out/
    runHook postInstall
  '';

  # Upstream suite (layout-tree rebuild + picker-parsing) with the patch
  # applied, so patch drift is caught by the build, not by usage.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${nodejs}/bin/node --test test.ts
    runHook postInstallCheck
  '';

  meta = {
    description = "Herdr plugin: move the focused tab or pane anywhere with an fzf picker, live agents included";
    homepage = "https://github.com/AVGVSTVS96/herdr-drovr";
    license = lib.licenses.mit;
  };
})
