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

  # Older bases pinned the bundled CLI in packages/electron/package.json and
  # gui.nix refused to build unless it matched; that pin is gone, so the
  # override below only applies where it still exists.
  electronManifest = lib.importJSON "${source.upstream}/packages/electron/package.json";
  cliPinCheck =
    if electronManifest ? opencodeCli
    then ''*"v${electronManifest.opencodeCli.version}"*) ;;''
    else null;

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
package.overrideAttrs (
  finalAttrs: previousAttrs:
  lib.optionalAttrs (cliPinCheck != null) {
    # gui.nix fails the build unless the bundled CLI is exactly the version
    # packages/electron pins. jkpkgs' opencode tracks its own releases, so
    # accept any version rather than coupling the two packages' bumps.
    installPhase =
      assert lib.hasInfix cliPinCheck previousAttrs.installPhase;
      lib.replaceStrings [ cliPinCheck ] [ "*) ;;" ] previousAttrs.installPhase;
  }
  // {
    # The Electron main process imports the i18n dictionaries straight from
    # packages/ui (idle-update-locales.mjs), but upstream's gui.nix copies
    # only packages/electron into the app tree. Copy the ui sources beside
    # it so bundle:main resolves those imports.
    buildPhase =
      assert lib.hasInfix "cp -a packages/electron ./app/packages/electron" previousAttrs.buildPhase;
      lib.replaceStrings
        [ "cp -a packages/electron ./app/packages/electron" ]
        [ "cp -a packages/electron ./app/packages/electron\n    cp -a packages/ui ./app/packages/ui" ]
        previousAttrs.buildPhase;
    passthru = previousAttrs.passthru // {
      tests = previousAttrs.passthru.tests or { } // {
        # The desktop's main process imports @openchamber/web/server/*,
        # which this base's package exports map to build/server/*. A core
        # tree without build/ builds fine and then crashes Electron at
        # startup with ERR_MODULE_NOT_FOUND, so resolve every such
        # specifier against the packaged app here.
        desktopEntryModules = pkgs.testers.runCommand {
          name = "openchamber-desktop-entry-modules-test";
          nativeBuildInputs = [
            pkgs.nodejs
            pkgs.gnugrep
          ];
          script = ''
            app=${finalAttrs.finalPackage}/share/openchamber/resources/app
            specs="$(grep -ohE '"@openchamber/web/[^"]+"' "$app"/dist-bundle/*.mjs | tr -d '"' | sort -u)"
            [ -n "$specs" ] || {
              echo "no @openchamber/web imports found in dist-bundle"
              exit 1
            }
            while IFS= read -r spec; do
              ( cd "$app" && node -e 'require.resolve(process.argv[1])' "$spec" ) || {
                echo "unresolved import: $spec"
                exit 1
              }
            done <<< "$specs"
            touch "$out"
          '';
        };
      };
    };
  }
)
