# Shared inputs for the OpenChamber web and desktop packages: the pinned
# upstream source with jkpkgs' patch queue applied, and the bun that builds
# and runs it.
#
# A local change to OpenChamber is a patch file listed here, not a fork or
# an edit to minified dist output. A patch that no longer applies after an
# upstream bump fails the build loudly.
#
# Everything read at evaluation time (version, bun pin, Electron pin, the
# desktop recipe) comes from the unpatched input, so evaluating another
# system's packages never has to build the patched tree first.
{
  lib,
  applyPatches,
  bun,
  fetchurl,
  stdenvNoCC,
  openchamberSource,
}:

let
  hashes = lib.importJSON ./hashes.json;
  upstreamPackage = lib.importJSON "${openchamberSource}/package.json";
  inherit (upstreamPackage) version;
  packageManagerBun = lib.removePrefix "bun@" upstreamPackage.packageManager;

  # The dependency fixed-output derivation is produced by `bun install`, and
  # its bytes depend on the bun version. Consumers override jkpkgs' nixpkgs
  # (navi and cedar ship different bun releases), so the bun is pinned here
  # to keep one bunDeps hash valid on every host. It tracks upstream's
  # packageManager pin, which is also the bun the server runs under.
  bunAssets = {
    x86_64-linux = "bun-linux-x64-baseline";
    aarch64-linux = "bun-linux-aarch64";
    aarch64-darwin = "bun-darwin-aarch64";
  };
  bunSources = lib.mapAttrs (
    system: asset:
    fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${hashes.bun.version}/${asset}.zip";
      hash = hashes.bun.hashes.${system};
    }
  ) bunAssets;
  pinnedBun = bun.overrideAttrs (old: {
    version = hashes.bun.version;
    src = bunSources.${stdenvNoCC.hostPlatform.system};
    passthru = old.passthru // {
      sources = bunSources;
    };
  });

  src = applyPatches {
    name = "openchamber-${version}-source";
    src = openchamberSource;
    patches = [
      ./patches/commandcode-quota.patch
      ./patches/question-indicator-purple.patch
      ./patches/chat-width.patch
      ./patches/symlink-file-refresh.patch
    ];
  };
in
# An upstream bun bump changes the lockfile contract and the server runtime,
# so it fails evaluation here instead of building against a stale bun.
lib.throwIf (hashes.bun.version != packageManagerBun)
  "openchamber ${version} pins bun@${packageManagerBun}, but packages/openchamber/hashes.json pins bun ${hashes.bun.version}; update bun.version and bun.hashes"
  {
    inherit version src;
    upstream = openchamberSource;
    bun = pinnedBun;
    inherit (hashes) bunDeps;
  }
