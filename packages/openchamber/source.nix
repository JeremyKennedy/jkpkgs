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
      ./patches/codex-credits-balance.patch
      # The badge work: both patches share the session switchers, so they are
      # ported together; upstream had already changed the unread condition and
      # the pending-request lookup these build on.
      ./patches/question-indicator.patch
      ./patches/stale-pending-badge.patch
      ./patches/reply-start-scroll.patch
      ./patches/dictation-thread-count.patch
      ./patches/dictation-sherpa-platform.patch
      # The rest of the local queue, rebased onto v2.7.2. Upstream absorbed
      # the chat width, notification-dismiss, guest-extension and
      # send-past-open-question patches (maintainer and contributor work, not
      # these PRs), so those are gone; what remains changes behaviour upstream
      # does not have yet.
      ./patches/draft-heading-project-picker.patch
      ./patches/recap-full-note.patch
      ./patches/image-viewer-zoom.patch
      ./patches/mobile-assist-trigger.patch
      ./patches/mobile-voice-launch.patch
      ./patches/dictation-recovery.patch
      ./patches/instance-attention.patch
      ./patches/question-rows.patch
      ./patches/question-cards.patch
      # Only the attention ranking of In work: v2.7.2's
      # `sidebarSessionBatchSize` already pages the block.
      ./patches/in-work-paging.patch
      ./patches/hide-empty-worktrees.patch
      # Gitea/Forgejo across-repository listing; upstream still gates
      # `referencesAcross` off for Gitea (#6345 is closed).
      ./patches/gitea-references-across.patch
      # Restored after the v2.7.2 port retired them on a wrong "upstream has
      # it" reading: a send with an open question steers into its turn
      # (upstream main's #6960 defers instead; reconcile on upgrade), and
      # viewing a session clears its subagents' phone banners on top of
      # upstream's server-side clearing.
      ./patches/send-past-open-question.patch
      # The phone removes its own delivered banners when the session is opened
      # or marked seen; the server's clearing push alone leaves a banner whose
      # push was missed.
      ./patches/android-notification-dismiss.patch
      ./patches/notification-family-clear.patch
      # Chat width levels the retired chat-width patch stored (and its
      # version-2 preferences.json) read as v2.7.2's levels.
      ./patches/chat-width-remap.patch
      # An 80rem level between Wider and Full, for messages and composer. It
      # edits the same level maps as the remap above, so it must follow it.
      ./patches/chat-width-80.patch
      # In work paging and its page-size setting; v2.7.2 lists every work.
      ./patches/in-work-paging-show-more.patch
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
