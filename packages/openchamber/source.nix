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
    # GNU patch defaults to fuzz 2: a hunk whose context no longer matches
    # applies anyway, possibly in the wrong place, and the build stays green.
    # At fuzz 0 every context line must match, so a bump that moves a hunk's
    # surroundings fails here and the patch gets re-exported.
    patchFlags = [
      "-p1"
      "--fuzz=0"
    ];
    patches = [
      ./patches/commandcode-quota.patch
      # The permission shield and question mark, drawn by one component with a
      # question colour of their own, on rows, switchers and collapsed headers;
      # a collapsed header and the switchers count pending requests by the
      # directory store once it has read them, as a row does. Carries the
      # remainder of the stale-pending-badge fix, which goes upstream with it.
      ./patches/question-indicator.patch
      ./patches/reply-start-scroll.patch
      ./patches/draft-heading-project-picker.patch
      ./patches/recap-full-note.patch
      ./patches/image-viewer-zoom.patch
      # The pdf.js fallback used where a runtime has no PDF viewer (the Android
      # WebView) gets the image viewer's zoom controls, pinch and wheel zoom.
      # It imports ImageZoomControls and wheelZoomFactor, so it follows the
      # image viewer patch.
      ./patches/pdf-viewer-zoom.patch
      ./patches/dictation-recovery.patch
      # Cross-instance attention, with its two fixes folded in: a question that
      # ends in error is checked against OpenCode's own form list before it is
      # shown, and a click in the attention dialog opens the clicked session
      # once the host switch lands.
      ./patches/instance-attention.patch
      ./patches/in-work-paging.patch
      ./patches/hide-empty-worktrees.patch
      ./patches/chat-width-80.patch
      ./patches/in-work-paging-show-more.patch
      ./patches/question-rows.patch
      # The question card, and the mark that tells a question line from a
      # collapsed quote.
      ./patches/question-cards.patch
      # The reference picker's search across every repository under a
      # project folder, for Gitea and Forgejo.
      ./patches/gitea-references-across.patch
      # The tray keeps one snapshot per window, grouped by instance, and sends
      # each row's click or answer to the window that supplied it. It touches
      # the runtime and sync files instance-attention changes, so it follows it.
      ./patches/tray-instances.patch
      # The attention popover lists another instance's sessions by that
      # instance's sidebar row rule, the same one its own view uses, so a
      # session its sidebar hides is not listed from elsewhere either.
      ./patches/attention-row-parity.patch
      # Where a session opens: the remembered position, the start of the last
      # reply, or the conversation start. It reads the reply start
      # reply-start-scroll computes, so it follows that patch.
      ./patches/session-entry-position.patch
      # A catalog change is announced by every running OpenCode location, and
      # the refresh re-read each one, so an OpenCode restart during it booted
      # every announcing location again. The refresh now reads only the
      # directories in use and marks the rest stale.
      ./patches/catalog-refresh-in-use.patch
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
