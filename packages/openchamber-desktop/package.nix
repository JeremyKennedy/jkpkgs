# OpenChamber Desktop built from the same patched source and core as the
# web package (packages/openchamber), with upstream's nix/gui.nix recipe and
# nixpkgs' Electron, so the patch queue reaches the desktop UI and its
# embedded server too.
#
# gui.nix and the files it reads through `self` (the electron package.json,
# preload.mjs, icons) come from the unpatched input so evaluation never
# builds the patched tree; a patch to those few files would not reach the
# desktop. The bundled main process is built from the patched tree.
{
  lib,
  callPackage,
  openchamber,
  opencode,
  pkgs,
}:

let
  inherit (openchamber.passthru) source;

  # The Electron major comes from packages/electron's devDependency, as in
  # upstream's flake, so an upstream major bump fails evaluation by name
  # instead of shipping a desktop that crashes at startup.
  electronSpec =
    (lib.importJSON "${source.upstream}/packages/electron/package.json").devDependencies.electron;
  electronMajor = lib.versions.major (lib.removePrefix "^" electronSpec);
  electron =
    pkgs."electron_${electronMajor}"
      or (throw "openchamber ${source.version} pins electron ${electronSpec}, but this nixpkgs has no electron_${electronMajor}");

  opencodeCliVersion =
    (lib.importJSON "${source.upstream}/packages/electron/package.json").opencodeCli.version;
  cliPinCheck = ''*"v${opencodeCliVersion}"*) ;;'';

  package = callPackage "${source.upstream}/nix/gui.nix" {
    inherit (source) bun version src;
    inherit electron;
    self = source.upstream;
    openchamberCore = openchamber.passthru.core;
    # The desktop launcher in dotfiles attaches to the managed OpenCode
    # server, so the bundled CLI is only a fallback. jkpkgs' opencode is
    # used instead of building upstream's pinned tag from source.
    opencodeCli = opencode;
  };
in
package.overrideAttrs (previousAttrs: {
  # gui.nix fails the build unless the bundled CLI is exactly the version
  # packages/electron pins. jkpkgs' opencode tracks its own releases, so
  # accept any version rather than coupling the two packages' bumps.
  installPhase =
    assert lib.hasInfix cliPinCheck previousAttrs.installPhase;
    lib.replaceStrings [ cliPinCheck ] [ "*) ;;" ] previousAttrs.installPhase;
})
