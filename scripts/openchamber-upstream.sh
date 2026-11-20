#!/usr/bin/env bash
# What does an upstream release mean for each OpenChamber patch?
#
# For every patch in the queue, this applies it alone to a pristine copy of a
# target tag and reports one verdict:
#
#   retire      the patch changes nothing against that tag, so upstream already
#               carries it; drop the patch, its source.nix entry and its
#               markers.json entry
#   reconcile   upstream shipped something for the same need but not this
#               change, or a declared-merged patch still adds content; read the
#               patch against the tag and decide drop / shrink / re-express
#   port        the patch no longer applies; it needs re-expressing before the
#               base moves
#   keep        still ours, and a declared request is open or it is local only
#   wait        merged upstream but no release contains it yet; keep it until one does
#   no-record   the patch has no entry in upstream.json; add one
#
# A patch is only ever retired on content, never on a commit message: the
# `retire` verdict means applying it to the tag produces byte-identical files.
#
# --single <patch> answers the other question, for one patch: does the tag
# already contain this change, and what does the patch actually add on top of
# the queue prefix it ships in? It extracts the tag fresh, applies every queued
# patch before it in source.nix order, applies it, and prints the diffstat that
# arrived. Nothing is cached or reused, so a scratch tree left over from an
# earlier run, or a checkout with the queue applied, cannot answer for it. That
# matters: an absorb check run against a tree that was already patched reported
# a patch as absorbed twice, because the change was there before it started.
#
# Exit codes:
#   0   the patch applies and adds content
#   1   usage error, unknown patch, or no tag
#   2   the patch does not apply, or applies but adds nothing: it is absorbed
#
# Usage:
#   scripts/openchamber-upstream.sh --upstream ~/dev/openchamber [--tag v2.7.2] [--json]
#   scripts/openchamber-upstream.sh --upstream ~/dev/openchamber --single <patch> [--tag v2.7.2] [--json]
#   scripts/openchamber-upstream.sh --backlog
#
# --upstream is a checkout of openchamber/openchamber with the tag fetched. The
# script copies the tag into a scratch directory and never touches the checkout.
#
# --single takes the patch name as source.nix writes it, with or without the
# `.patch` suffix. Its prefix is applied the way the whole-queue run applies it,
# in queue order, so a patch that builds on an earlier one is judged in the tree
# it actually ships in. The diffstat is computed from the files before and after
# that one patch, not from the patch's own headers.
#
# --backlog needs no checkout and no network: it reads upstream.json alone and
# prints every patch and candidate as upstream work owed, grouped by intent in
# the order bugfix, feature, personal, testing, declined. That is the answer to
# "what still needs to go upstream".
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_dir="$repo_root/packages/openchamber"
ledger="$package_dir/upstream.json"
upstream=""
tag=""
json=0
backlog=0
single=""

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --upstream) upstream="$2"; shift 2 ;;
    --tag) tag="$2"; shift 2 ;;
    --json) json=1; shift ;;
    --backlog) backlog=1; shift ;;
    --single)
      [ $# -ge 2 ] || { echo "--single needs a patch name" >&2; exit 1; }
      single="${2%.patch}"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

[ -f "$ledger" ] || { echo "missing $ledger" >&2; exit 1; }

if [ "$backlog" -eq 1 ]; then
  python3 - "$ledger" "$package_dir/source.nix" <<'PY'
import json, re, sys

ledger_path, source_path = sys.argv[1], sys.argv[2]
data = json.load(open(ledger_path))
records = data.get("patches") or {}
candidates = data.get("candidates") or []
queue = re.findall(r"patches/([a-z0-9._-]+)\.patch", open(source_path).read())

order = ["bugfix", "feature", "personal", "testing", "declined"]


def reference(record):
    if record.get("pr"):
        ref = "PR #%s" % record["pr"]
    elif record.get("issue"):
        ref = "issue #%s" % record["issue"]
    else:
        ref = "-"
    if record.get("mergedAs"):
        ref += " (merged)"
    return ref


groups = {intent: [] for intent in order}
for name in queue:
    record = records.get(name) or {}
    groups.setdefault(record.get("intent") or "(no intent)", []).append(
        (name, record.get("relationship") or "-", reference(record), record.get("note") or "-")
    )
for candidate in candidates:
    groups.setdefault(candidate.get("intent") or "(no intent)", []).append(
        (
            candidate.get("name") or "?",
            "candidate",
            reference(candidate),
            candidate.get("note") or "-",
        )
    )

counts = ", ".join("%d %s" % (len(rows), intent) for intent, rows in groups.items() if rows)
print(
    "OpenChamber upstream backlog: %d patches, %d candidate%s (%s)"
    % (len(queue), len(candidates), "" if len(candidates) == 1 else "s", counts)
)
print()
print("relationship: same | alternative | partial | pending | none. candidate = local patch not written yet.")
print()
name_width = max([34] + [len(name) for rows in groups.values() for name, _, _, _ in rows])
for intent, rows in groups.items():
    if not rows:
        continue
    print("%s (%d)" % (intent, len(rows)))
    for name, relationship, ref, note in rows:
        print("  %-*s %-11s %-20s %s" % (name_width, name, relationship, ref, note))
    print()
PY
  exit 0
fi

[ -n "$upstream" ] || { echo "--upstream is required" >&2; exit 1; }
[ -d "$upstream/.git" ] || { echo "$upstream is not a git checkout" >&2; exit 1; }

if [ -z "$tag" ]; then
  tag=$(git -C "$upstream" tag --sort=-v:refname | head -1)
fi
git -C "$upstream" rev-parse -q --verify "$tag^{commit}" >/dev/null || { echo "no such tag: $tag" >&2; exit 1; }

queue=$(sed -n '/patches = \[/,/\]/p' "$package_dir/source.nix" | grep -o '[a-z0-9._-]*\.patch' | sed 's/\.patch$//')

scratch=$(mktemp -d "${TMPDIR:-/tmp}/oc-upstream-XXXXXX")
trap 'rm -rf "$scratch"' EXIT

git -C "$upstream" archive "$tag" | tar -x -C "$scratch"

# A patch's touched paths, from its own headers.
touched() {
  grep -E '^(---|\+\+\+) ' "$1" | sed -e 's#^--- [ab]/##' -e 's#^+++ [ab]/##' -e 's#^--- /dev/null##' -e 's#^+++ /dev/null##' | sed '/^$/d' | sort -u
}

# The paths a patch expects to find, from its `---` headers alone.
old_paths() {
  grep -E '^--- ' "$1" | sed -e 's#^--- [ab]/##' -e 's#^--- /dev/null##' | sed '/^$/d' | sort -u
}

if [ -n "$single" ]; then
  # One patch, one question: on this tag, with the queue prefix it ships in,
  # does it add anything? The tag was extracted fresh above and the scratch
  # directory is this invocation's alone, so a leftover tree or a patched
  # checkout has no way to answer for it.
  case " $(printf '%s ' $queue) " in
    *" $single "*) ;;
    *) echo "unknown patch: $single (not in the source.nix queue)" >&2; exit 1 ;;
  esac

  patch_file="$package_dir/patches/$single.patch"
  [ -f "$patch_file" ] || { echo "patch file missing: $patch_file" >&2; exit 1; }

  prefix_total=0
  prefix_full=0
  prefix_partial=()

  for prev in $queue; do
    [ "$prev" = "$single" ] && break
    prefix_total=$((prefix_total + 1))
    prev_file="$package_dir/patches/$prev.patch"
    if [ ! -f "$prev_file" ]; then
      prefix_partial+=("$prev (no patch file)")
      continue
    fi
    # Same apply as the whole-queue run, and the same tolerance of a partial
    # one: the prefix is the tree this patch ships in, not a clean-room ideal.
    if (cd "$scratch" && patch -p1 --forward --batch --quiet < "$prev_file" >/dev/null 2>&1); then
      prefix_full=$((prefix_full + 1))
    else
      prefix_partial+=("$prev")
    fi
    # A rejected hunk's .rej is not part of any tree; drop it so it cannot
    # reach the diffstat. `.orig` is the backup `patch` writes when a hunk
    # lands at an offset, not a failure, so it is removed too but never
    # counted as one.
    find "$scratch" \( -name '*.rej' -o -name '*.orig' \) -delete
  done

  # The prefix tree is the baseline, so the diffstat is what this patch adds on
  # top of it: a commit of that state, then the working tree after the apply.
  # The scratch repo is throwaway, so it runs with no user or system git config
  # and its own hooks path: a global autocrlf, eol attribute or commit hook must
  # not change what the tag's own files diff to.
  git_env=(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_ATTR_NOSYSTEM=1)
  env "${git_env[@]}" git -C "$scratch" init -q
  env "${git_env[@]}" git -C "$scratch" add -Af .
  env "${git_env[@]}" git -C "$scratch" \
    -c user.name=openchamber-upstream -c user.email=openchamber-upstream@invalid \
    -c core.autocrlf=false -c core.hooksPath=/dev/null \
    commit -qm "$tag with queue prefix"

  stat_rows=""
  missing=()
  failed_hunks=0
  first_complaint=""
  state=applies

  # Paths the patch expects that the prefix tree does not have. This is the
  # usual reason a port is needed (a `.js` file the tag turned into `.ts`), and
  # it reads better than patch's own header text.
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ -e "$scratch/$path" ] || missing+=("$path")
  done < <(old_paths "$patch_file")

  if ! output=$(cd "$scratch" && patch -p1 --forward --batch --dry-run < "$patch_file" 2>&1); then
    failed_hunks=$(printf '%s\n' "$output" | grep -cE '^Hunk #[0-9]+ (FAILED|ignored)|hunks? (failed|ignored)')
    first_complaint=$(printf '%s\n' "$output" | grep -vE '^(checking file|Hunk #[0-9]+ succeeded|.*offset [0-9]+ lines)' | grep -v '^$' | head -1)
    # A patch already present fails --forward as "previously applied"; the
    # reverse dry-run tells an absorbed patch apart from one that needs a port.
    if [ "${#missing[@]}" -eq 0 ] \
       && (cd "$scratch" && patch -p1 --forward -R --batch --dry-run --quiet < "$patch_file" >/dev/null 2>&1); then
      state=absorbed
    else
      state=no-apply
    fi
  fi

  if [ "$state" = "applies" ]; then
    (cd "$scratch" && patch -p1 --forward --batch --quiet < "$patch_file" >/dev/null 2>&1)
    if [ -n "$(find "$scratch" -name '*.rej' -print -quit)" ]; then
      state=no-apply
    else
      # Offsets make patch leave .orig backups; they are not part of the change.
      find "$scratch" -name '*.orig' -delete
      env "${git_env[@]}" git -C "$scratch" add -Af .
      stat_rows=$(env "${git_env[@]}" git -C "$scratch" diff --cached --numstat --no-renames HEAD)
      # Applied, but the tag already holds the content byte for byte.
      [ -n "$stat_rows" ] || state=absorbed
    fi
  fi

  if [ "$json" -eq 1 ]; then
    skipped_file="$scratch/.prefix-partial"
    printf '%s\n' "${prefix_partial[@]}" > "$skipped_file"
    printf '%s\n' "${missing[@]}" > "$scratch/.missing"
    python3 - "$tag" "$single" "$state" "$prefix_total" "$prefix_full" \
      "$skipped_file" "$scratch/.missing" "$stat_rows" <<'PY'
import json, sys

tag, patch, state, total, full, partial_path, missing_path, stat_rows = sys.argv[1:9]
read = lambda p: [line for line in open(p).read().splitlines() if line]
files, insertions, deletions = [], 0, 0
for row in stat_rows.splitlines():
    added, removed, path = row.split("\t", 2)
    binary = added == "-"
    files.append({
        "path": path,
        "added": None if binary else int(added),
        "deleted": None if binary else int(removed),
    })
    if not binary:
        insertions += int(added)
        deletions += int(removed)
print(json.dumps({
    "tag": tag,
    "patch": patch,
    "state": state,
    "prefix": {"queued": int(total), "applied": int(full), "partial": read(partial_path)},
    "missing": read(missing_path),
    "files": files,
    "totals": {"files": len(files), "insertions": insertions, "deletions": deletions},
}, indent=2))
PY
  else
    printf 'target tag: %s\n' "$tag"
    printf 'patch:      %s\n' "$single"
    prefix_line="$prefix_full of $prefix_total queued patches applied"
    if [ "${#prefix_partial[@]}" -gt 0 ]; then
      prefix_line="$prefix_line; partial: $(IFS=', '; echo "${prefix_partial[*]}")"
    fi
    printf 'prefix:     %s\n' "$prefix_line"
    case "$state" in
      applies) printf 'state:      applies cleanly\n' ;;
      absorbed) printf 'state:      absorbed, the tag already has this content\n' ;;
      no-apply) printf 'state:      does not apply\n' ;;
    esac
    if [ "$state" = "applies" ]; then
      printf '\n'
      printf '%-52s %8s %8s\n' FILE ADDED DELETED
      while IFS=$'\t' read -r added removed path; do
        [ -n "$path" ] || continue
        printf '%-52s %8s %8s\n' "$path" "$added" "$removed"
      done <<< "$stat_rows"
      printf '\n'
      env "${git_env[@]}" git -C "$scratch" diff --cached --shortstat --no-renames HEAD
    elif [ "$state" = "no-apply" ] && [ "${#missing[@]}" -gt 0 ]; then
      printf 'missing:    %d of the %d files it patches are not in %s\n' \
        "${#missing[@]}" "$(old_paths "$patch_file" | wc -l)" "$tag"
      printf '  %s\n' "${missing[@]}"
    elif [ "$state" = "no-apply" ]; then
      printf 'failed:     %d hunks no longer match\n' "$failed_hunks"
    fi
    if [ "$state" = "no-apply" ] && [ -n "$first_complaint" ]; then
      printf 'first:      %s\n' "$first_complaint"
    fi
  fi

  [ "$state" = "applies" ] || exit 2
  exit 0
fi

record_field() {
  # record_field <patch> <field>: prints the field, or empty.
  python3 - "$ledger" "$1" "$2" <<'PY'
import json, sys
ledger, patch, field = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = json.load(open(ledger))
except Exception:
    print("")
    sys.exit(0)
entry = (data.get("patches") or {}).get(patch)
print("" if not entry else (entry.get(field) or ""))
PY
}

results=()

snapshot() {
  # snapshot <tree> <patch-file>: a stable digest of the files a patch touches.
  local tree="$1" patch_file="$2" path digest
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$tree/$path" ]; then
      digest=$(md5sum < "$tree/$path" | cut -d' ' -f1)
    else
      digest=absent
    fi
    printf '%s %s\n' "$path" "$digest"
  done < <(touched "$patch_file")
}

for name in $queue; do
  patch_file="$package_dir/patches/$name.patch"
  relationship=$(record_field "$name" relationship)

  if [ ! -f "$patch_file" ]; then
    results+=("$name|no-record|patch file missing")
    continue
  fi
  if [ -z "$relationship" ]; then
    results+=("$name|no-record|add it to upstream.json")
    continue
  fi

  # Apply in queue order, so a patch that builds on an earlier one is judged in
  # the tree it actually ships in.
  before=$(snapshot "$scratch" "$patch_file")
  if ! (cd "$scratch" && patch -p1 --forward --batch --quiet < "$patch_file" >/dev/null 2>&1) \
     || [ -n "$(find "$scratch" -name '*.rej' -print -quit)" ]; then
    results+=("$name|port|does not apply in queue order to $tag")
    continue
  fi
  after=$(snapshot "$scratch" "$patch_file")

  if [ "$before" = "$after" ]; then
    if [ "$relationship" = "same" ]; then
      results+=("$name|retire|$tag already has this content")
    elif [ "$relationship" = "pending" ]; then
      results+=("$name|reconcile|declared pending, but $tag already has this content")
    else
      results+=("$name|reconcile|adds nothing on $tag")
    fi
    continue
  fi

  case "$relationship" in
    same)
      released=$(record_field "$name" release)
      if [ -n "$released" ] && [ "$released" != "$tag" ]; then
        results+=("$name|wait|merged upstream, not in $tag yet")
      else
        results+=("$name|reconcile|declared merged, but it still adds content on $tag")
      fi
      ;;
    alternative|partial) results+=("$name|reconcile|upstream shipped a different design for this need") ;;
    pending) results+=("$name|keep|request open") ;;
    none) results+=("$name|keep|local only") ;;
    *) results+=("$name|no-record|unknown relationship '$relationship'") ;;
  esac
done

# A record with no queued patch is stale itself.
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if ! printf '%s\n' $queue | grep -qx "$name"; then
    results+=("$name|no-record|record exists but the patch is not in the queue")
  fi
done < <(python3 - "$ledger" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for name in (data.get("patches") or {}):
    print(name)
PY
)

if [ "$json" -eq 1 ]; then
  python3 - "$tag" "${results[@]}" <<'PY'
import json, sys
tag, rows = sys.argv[1], []
for item in sys.argv[2:]:
    name, verdict, detail = item.split("|", 2)
    rows.append({"patch": name, "verdict": verdict, "detail": detail})
print(json.dumps({"tag": tag, "patches": rows}, indent=2))
PY
else
  printf 'target tag: %s\n\n' "$tag"
  printf '%-34s %-10s %s\n' PATCH VERDICT DETAIL
  for item in "${results[@]}"; do
    IFS='|' read -r name verdict detail <<< "$item"
    printf '%-34s %-10s %s\n' "$name" "$verdict" "$detail"
  done
fi

action=0
for item in "${results[@]}"; do
  IFS='|' read -r _ verdict _ <<< "$item"
  case "$verdict" in retire|reconcile|port|no-record) action=1 ;; esac
done
[ "$action" -eq 0 ] || exit 2
