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
# Usage:
#   scripts/openchamber-upstream.sh --upstream ~/dev/openchamber [--tag v2.7.2] [--json]
#   scripts/openchamber-upstream.sh --backlog
#
# --upstream is a checkout of openchamber/openchamber with the tag fetched. The
# script copies the tag into a scratch directory and never touches the checkout.
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

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --upstream) upstream="$2"; shift 2 ;;
    --tag) tag="$2"; shift 2 ;;
    --json) json=1; shift ;;
    --backlog) backlog=1; shift ;;
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
  # the tree it actually ships in. Fuzz 0, the same as source.nix: a hunk that
  # applies here only with fuzz fails the build, so it is a port. The dry run
  # comes first so a patch that fails leaves no hunks and no .rej files behind,
  # and every later patch is judged on a tree that holds only applied patches.
  before=$(snapshot "$scratch" "$patch_file")
  apply=(patch -p1 --fuzz=0 --forward --batch --quiet)
  if ! (cd "$scratch" && "${apply[@]}" --dry-run < "$patch_file" >/dev/null 2>&1); then
    results+=("$name|port|does not apply in queue order to $tag")
    continue
  fi
  if ! (cd "$scratch" && "${apply[@]}" < "$patch_file" >/dev/null 2>&1); then
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
