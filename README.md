# jkpkgs

Personal binary packages for AI/LLM tools.

## Common commands

```bash
just check
just build
nix build .#pi
```

## Pi fast-track workflow

Use this when pi needs a model metadata update before the normal automated update cycle has reached navi.

### Normal released update

Prefer this whenever `@earendil-works/pi-coding-agent` is already published on npm.

1. Update the wrapper dependency:
   ```bash
   cd ~/dev/jkpkgs/packages/pi
   npm install @earendil-works/pi-coding-agent@<version> --package-lock-only --ignore-scripts
   ```
2. Update `packages/pi/hashes.json`:
   - `version` = the npm package version
   - `npmDepsHash` = the hash reported by a failed `nix build .#pi`, if it changed
3. Verify the package:
   ```bash
   cd ~/dev/jkpkgs
   nix build .#pi
   ./result/bin/pi --version
   ./result/bin/pi --list-models | grep '<model-or-family>'
   just check
   ```
4. Commit and push jkpkgs.
5. Activate it on navi through dotfiles:
   ```bash
   cd ~/dev/dotfiles
   dotman flake update jkpkgs
   dotman deploy --local
   ```
6. Verify the active profile, not just `~/dev/jkpkgs/result`:
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
3. Regenerate `packages/pi/package-lock.json` with `npm install --package-lock-only --ignore-scripts`.
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
