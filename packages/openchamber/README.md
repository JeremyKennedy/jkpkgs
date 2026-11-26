# OpenChamber package

An upstream release with a local patch queue. This file is the procedure for
moving the base, and it exists because a release port once retired fourteen
patches as "upstreamed" without checking, and lost local behaviour that way.

## Moving the base

`scripts/openchamber-upstream.sh` classifies every queued patch against a tag
and prints one verdict each:

| Verdict | Meaning | What to do |
|---|---|---|
| `retire` | Applying the patch to that tag changes nothing | Drop the patch, its `source.nix` entry and its `markers.json` entry |
| `wait` | Merged upstream, but no release contains it yet | Keep it until a tag does |
| `reconcile` | Upstream shipped a different design, or a declared-merged patch still adds content | Read the patch against the tag, then drop, shrink or re-express it |
| `port` | It no longer applies in queue order | Re-express it before the base moves |
| `keep` | Still ours; a request is open, or it is local only | Nothing |
| `no-record` | The patch has no entry in `upstream.json`, or the record has no patch | Add or remove the record |

Run it with the tag you are moving to:

```
just upstream v2.7.3
```

It exits non-zero when any patch needs a decision, so it belongs at the start
of a base bump, before `source.nix` changes. Every patch must have a verdict
before the queue moves.

Patches apply at fuzz 0, in `source.nix` and in the script. A hunk whose
context no longer matches fails the build; re-export the patch against the
tree it applies to. Never raise the fuzz to get a bump green: GNU patch's
default of 2 lets a hunk land wherever two lines of its context match.

Each patch carries its own work only. When patch B rewrites lines that an
earlier patch A added, `scripts/assert-openchamber-patch-overlap.mjs` fails
unless A is in B's `follows` in `upstream.json`. Declare it when B really builds
on A; otherwise the hunk belongs in A, and both patches get re-exported. A lint
cleanup of another patch's file is the usual case: it goes into that patch. The
shared settings files are listed by name in the script and are exempt.

Every patch has a `markers.json` entry. A `client` patch names a string that
must appear in the mobile bundle the APK packages, and the
`openchamber-mobile-markers` flake check asserts it: it runs upstream's
`prepare-web-assets.mjs` on the core's web build and greps the result with
`scripts/assert-patch-markers.sh`. That check is part of buildbot/nix-build,
a required status, so a patch whose marker is missing fails its pull request.
The Android smoke build runs the same script on the real APK tree, but only for
app paths and as an unrequired status.

A green `nix build .#checks.x86_64-linux.openchamber` proves the patches apply
and the version smoke test passes. It does **not** typecheck the server: run
`node packages/web/scripts/check-server-types.mjs` from the repository root of
the patched tree, after a fresh frozen install, and compare the count against
the same check on the bare tag. The tag is the baseline, and a bump is clean
when the count matches it rather than when it is zero.

### Measuring a bump

Four things that read as failures but are not, all of them hit during the
v2.7.3 port and each costing time to re-diagnose:

- **A fresh worktree with its own frozen install, every time.** Never copy
  `node_modules` between worktrees to save an install: the typecheck resolves
  typescript through the tree it runs in and then reports errors that belong to
  the copy. That produced a "164 pre-existing errors" report on a tag that is
  actually clean.
- **The tag is the baseline, not a zero target.** Measure the bare tag first and
  record the number, then compare. A lower count is not automatically a pass
  either: say so when the port incidentally fixes an upstream error rather than
  banking it as progress.
- **Server tests are vitest, not `bun test`.** `bun test` on
  `server/lib/notifications` reports around eighty failures per file because
  vitest's API (`vi.unstubAllGlobals`) is absent. Run
  `bunx vitest run <paths>` from `packages/web`.
- **Batch runs lie about UI suites.** The full `bun test` in `packages/ui`
  fails hundreds of tests in both trees (641 on the v2.7.3 port, 990 on the
  bare tag), so the raw count says nothing. Compare the failing-name sets
  between the two trees and re-run each name that differs on its own; on that
  bump 16 names differed and every one passed individually. Batch contamination
  is the cause: the files share process state.

And one habit worth keeping: before describing a code change as a behaviour fix,
revert it and watch the tests. A fix whose reversal leaves the suite green was
arity or naming, not behaviour, and the commit message should say so.

### Landing a bump

- Open the pull request, then merge with an explicit `--head <full sha>`.
  `dotman forgejo pr merge` refuses a short sha.
- An amend on a branch someone else is working from needs
  `--force-with-lease=<branch>:<sha>` pinned to the exact sha you believe is
  there. It refuses rather than clobbers, which is the whole point.
- Not all patches are the tag's shape: a patch written for a commit may carry
  `.js` paths where the tag has `.ts`, or the reverse. Check which one the
  target actually has before treating a rejection as a port.

## `upstream.json`

One record per patch, and the reason each patch exists:

- `relationship`: `same` (upstream has or will have this change), `alternative`
  (upstream shipped a different design for the same need), `partial`, `pending`
  (a PR or issue is open, nothing shipped) or `none` (local only).
- `intent`: what the patch deserves upstream — `bugfix` (a broken thing upstream
  owns), `feature`, `personal` (stays local), `testing` (wants more use before
  deciding) or `declined` (the maintainer refused it). `relationship` says what a
  release means for the patch; `intent` says what to do with it.
- `pr` / `issue`, `mergedAs` (merge commit), `release` (`unreleased` until a tag
  contains it), and a one-line `note`.

Update it in the same change that adds, drops or re-expresses a patch. The
script fails a patch that is in the queue without a record, a record with no
patch, and a record without an `intent`.

`candidates` is the other half: upstream work worth doing that has no local patch
yet, each with `name`, `intent`, `note` and `since`. A candidate becomes a patch
record when someone writes the patch, not before.

## Waiting for acceptance

A feature request goes upstream first, and the pull request opens alongside it.
The intake bot closes a feature PR until its request is `accepted`, and reopens
it on its own once that happens. That closed state is the normal waiting state,
not a verdict:

- keep the patch, and keep both `issue` and `pr` in its record with
  `relationship: pending`;
- do not drop a patch because the bot closed its PR;
- drop it when the request is declined, when it goes stale for long enough that
  nobody is going to act, or when upstream ships something else for the need
  (`alternative`, or `declined` for this exact patch).

Closing a PR by hand is the same: the patch stays unless the reason is one of
the three above. The queue's job is to carry the work until upstream takes it.

## The backlog

```
just upstream-backlog
```

Prints every patch and candidate grouped by intent, `bugfix` first and
`declined` last, with the relationship, the open PR or issue, and the note. It
reads `upstream.json` only, so it needs no upstream checkout and no network. Use
it to answer "what still needs to go upstream" before a batch of PRs or at a base
bump; `just upstream <tag>` answers the other question, whether an existing patch
survives a tag.

## Proving a patch before it is queued

A patch earns its place by changing what the running app does, not by being right in isolation.
Before it goes into `source.nix`:

1. Reproduce the problem in the app the patch is for, and write the number down first: a request
   count, a boot count, a latency percentile, whatever the patch is supposed to move.
2. Apply it, deploy, and measure the same number the same way. No difference means no patch.
3. If the number cannot be measured (a client bundle cached by the browser, a path only a rare
   event reaches), the patch is a draft upstream, not a local queue entry.

The 2026-11-24 reconnect patch is the example to keep: it removed a per-directory reconnect loop
that was correct to remove, but a deployed build still booted 268 locations after an OpenCode
restart, so the effect could not be shown. It was reverted from the queue and its upstream pull
request closed. The same night's message-search patch had its effect measured (MCP servers per
location 4 to 2) and stayed.

A second trap from the same night: a 404 is not proof that an endpoint is unsupported. On OpenCode
2.4.1 `/api/form` and `/api/permission/request` answer 200 for a loaded location and 404
(`LocationNotFoundError`) for a directory whose location was unloaded. Caching that as
"unsupported" would have disabled pending-form reads for the whole runtime; the test that stayed
red was right and the design was wrong.

## Retiring a patch

Only on content. The `retire` verdict means the patched files come out
byte-identical to the tag's own files. A merged pull request is not enough:
upstream sometimes merges an alternative, which is `reconcile`, not `retire`.

When a patch is retired, its behaviour must still be true of the new base. For
a patch whose tests live inside it, run them against the applied queue; for one
that changes what a user sees, exercise it in a throwaway build before the
deploy that follows the bump.
