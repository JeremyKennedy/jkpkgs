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

## `upstream.json`

One record per patch, and the reason each patch exists:

- `relationship`: `same` (upstream has or will have this change), `alternative`
  (upstream shipped a different design for the same need), `partial`, `pending`
  (a PR or issue is open, nothing shipped) or `none` (local only).
- `pr` / `issue`, `mergedAs` (merge commit), `release` (`unreleased` until a tag
  contains it), and a one-line `note`.

Update it in the same change that adds, drops or re-expresses a patch. The
script fails a patch that is in the queue without a record, and a record with
no patch.

## Retiring a patch

Only on content. The `retire` verdict means the patched files come out
byte-identical to the tag's own files. A merged pull request is not enough:
upstream sometimes merges an alternative, which is `reconcile`, not `retire`.

When a patch is retired, its behaviour must still be true of the new base. For
a patch whose tests live inside it, run them against the applied queue; for one
that changes what a user sees, exercise it in a throwaway build before the
deploy that follows the bump.
