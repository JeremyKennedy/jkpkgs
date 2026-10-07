# jkpkgs

Personal binary packages for AI/LLM tools.

## Package lifecycle

The standard flow for adding or updating a package:

1. Add `packages/<name>/package.nix` and version/hash metadata.
2. Add the package output; derive checks from the package set.
3. Register update metadata in dotman.
4. Stage new files before Git-backed Nix evaluation.
5. Run `just check` and `just build [name...]`.
6. Commit and push jkpkgs.
7. Use the existing dotman propagation workflow.
8. Verify the active profile, not only `./result`.

Notes:

- `just build` with no names builds all current-system packages.
- `dotman jkpkgs check` and `dotman jkpkgs list` are fully offline; only
  `dotman jkpkgs update` touches the network.
- An update may move several package versions at once — check the commit
  contents before propagating.
- Active dotfiles paths live under `~/dev/dots/dotfiles-personal`; this
  checkout is its sibling, `~/dev/dots/jkpkgs`.

## Herdr source lifecycle

Herdr is source-backed: the package builds from the upstream
`herdrdev/herdr` source (pinned by the `herdr` flake input in
`flake.lock`) with the explicit local patch queue under
`packages/herdr/patches` applied on top. Source packages carry no release
hashes — the flake lock pins the exact upstream source, unlike the
hash-pinned binary and npm packages.

To change Herdr locally, edit the patch queue (or `package.nix`), verify
with `nix build .#herdr`, then commit, push, and propagate as usual.

The `jkpkgs-refresh` timer invokes `dotman jkpkgs update --package-only`
for the automated refresh. Source packages are tracked in one of two
modes: Herdr follows upstream release tags (the evaluated package
version must match the release), while release-less upstreams like
herdr-drovr are commit-tracked — the flake input's locked rev is
compared to the branch head and the patched build itself is the drift
check. Either way the updater refreshes the flake input, builds the
patched package, and stops before any PR is created if the version
check, the patches, or the build fail. On success it stages only the
`flake.lock` change and proposes it through the same reviewed Forgejo
PR and Buildbot path as other updates. Consumer lock propagation and
host deployment remain a separate, manual workflow.

## Herdr plugin: herdr-drovr

`herdr-drovr` packages the upstream `AVGVSTVS96/herdr-drovr` plugin
(fzf picker to move panes/tabs across workspaces; live agents survive)
from the `drovr` flake input (pinned to upstream GitHub `main`) with
one local patch (`packages/herdr-drovr/patches/all-spaces-default.patch`:
the pane picker defaults to all workspaces instead of the current one).
The build has no fork dependency: the patch queue carries the change
exactly like Herdr's does. Upstream publishes no releases, so dotman
tracks the `drovr` input by commit (`flake.lock` rev versus GitHub
`main`'s head): the refresh timer proposes the pin bump and the
install-check build rejects a broken patch queue before any PR lands.
`forgejo:jeremy/herdr-drovr` is a custody mirror only — its `main` is
upstream plus the same patch commit, and a weekly Forgejo Action
force-syncs its `upstream` branch so the patched lineage can never be
orphaned by upstream force-pushes. Nothing builds from that mirror, and
it runs no drift detection; the timer owns that.

The store path *is* the plugin directory: activate with
`herdr plugin link ${pkgs.herdr-drovr}` (idempotent; relinking repoints
the running server at a new build). The install-check phase runs
upstream's node test suite against the patched source, so patch drift
fails the build like Herdr's queue does. Regenerate the patch against
the pinned input with `git diff upstream/main -- package-lock.json pick-and-move.ts`
(the lockfile hunk renames the stale upstream package name).

## Common commands

```bash
just check
just build
nix build .#pi
```

## CI

Merges to `main` are gated on buildbot status contexts; the live list for
this repo is the Forgejo branch-protection config (`status_check_contexts`)
or `dotman buildbot status jeremy/jkpkgs`. CI evaluates all systems but
builds only `x86_64-linux`, so darwin outputs (dsh, paseo on Cedar) are
proven by evaluation here and by the actual download/build on the target
machine at deploy time.

## Pi fast-track workflow

Use this when pi needs a model metadata update before the normal automated update cycle has reached navi.

### Normal released update

Prefer this whenever `@earendil-works/pi-coding-agent` is already published on npm.
1. Check whether npm already has the version you need:
   ```bash
   npm view @earendil-works/pi-coding-agent version
   ```
2. Update `packages/pi/package.json` and regenerate its lockfile:
   ```bash
   npm --prefix packages/pi install @earendil-works/pi-coding-agent@<version> --package-lock-only --ignore-scripts
   ```
3. Update `packages/pi/hashes.json`:
   - `version` = the npm package version
   - `npmDepsHash` = the hash reported by a failed `nix build .#pi`, if it changed
4. Verify the package:
   ```bash
   cd ~/dev/dots/jkpkgs
   nix build .#pi
   ./result/bin/pi --version
   ./result/bin/pi --list-models | grep '<model-or-family>'
   just check
   ```
5. Commit and push jkpkgs.
6. Activate it on navi through dotfiles:
   ```bash
   cd ~/dev/dots/dotfiles-personal
   dotman flake update jkpkgs
   dotman deploy --local
   ```
7. Verify the active profile, not just `~/dev/dots/jkpkgs/result`:
   ```bash
   hash -r
   command -v pi
   readlink -f "$(command -v pi)"
   pi --version
   pi --list-models | grep '<model-or-family>'
   ```

### Emergency unreleased acceleration

Use this only when upstream pi has the needed change on GitHub but npm has not published it yet.

First consider a local-only override in `~/.pi/agent/models.json`. That is fastest and avoids package drift if only one machine needs the model.

If the packaged `pi` must carry the change:

1. Find the upstream commit and issue/PR that contains the metadata.
2. Prefer backporting the upstream generated metadata over hand-editing one line. Pi model support commonly touches generator source, generated provider catalogs, tests, and changelogs.
3. Make the temporary nature obvious:
   - version like `0.80.3-unstable-YYYY-MM-DD`, or
   - a clearly named backport script with the upstream commit URL in a comment
4. Add a build-time assertion that the expected model exists.
5. Verify the package and active profile using the same commands as the normal update.
6. Commit and push jkpkgs, then update/deploy dotfiles.

Do not mark the work done because `./result/bin/pi` works. The user-visible binary is the one from the active profile (`command -v pi`).

### Returning pi to normal releases

When npm publishes a pi release containing the temporary backport:

1. Remove any temporary patch, source pin, or backport script.
2. Set `packages/pi/package.json` to the released `@earendil-works/pi-coding-agent` version.
3. Regenerate `packages/pi/package-lock.json` with:
   npm --prefix packages/pi install @earendil-works/pi-coding-agent@<version> --package-lock-only --ignore-scripts
4. Set `packages/pi/hashes.json.version` to the real release version, with no `unstable` suffix.
5. Refresh `npmDepsHash` from `nix build .#pi` if needed.
6. Check that no temporary backport remains:
   ```bash
   rg 'unstable|backport|gpt-5\.6|temporary' packages/pi
   ```
   The model name may still appear only if it is part of the released package data, not a local patch.
7. Verify and deploy through dotfiles as usual.

### GPT-5.6 verification example

This is the checklist used for the GPT-5.6 fast-track incident:

```bash
hash -r
command -v pi
readlink -f "$(command -v pi)"
pi --version
pi --list-models | grep 'gpt-5\.6'
pi --print --no-tools --no-session --model openai-codex/gpt-5.6-sol 'Respond with exactly: hello world'
```

Expected final prompt output:

```text
hello world
```
