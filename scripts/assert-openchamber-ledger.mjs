#!/usr/bin/env node
// Offline gate for the OpenChamber patch ledger.
//
// Every patch in the queue must have a record in packages/openchamber/upstream.json
// saying what it is to upstream and what it deserves upstream, and every record
// must belong to a queued patch. Intended upstream work with no patch yet is a
// candidate, and carries the same intent.
// This runs inside `just check`, so a patch cannot be added, dropped or
// re-expressed without saying what it is and whether upstream has it.
//
// It also checks that the queue is the patch directory: every .patch file in
// packages/openchamber/patches is queued, and every queued patch has its file and
// a markers.json entry. The android release asserts markers against the
// directory, not the queue, so a patch file left behind by a bump passes every
// other gate and fails only the release build, after merge.
//
// It does not talk to the network. Whether a release already contains a patch is
// `just upstream <tag>`, run at a base bump. What is still owed upstream is
// `just upstream-backlog`.

import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const packageDir = join(repoRoot, 'packages', 'openchamber');
const ledgerPath = join(packageDir, 'upstream.json');
const sourcePath = join(packageDir, 'source.nix');

const RELATIONSHIPS = new Set(['same', 'alternative', 'partial', 'pending', 'none']);
const INTENTS = new Set(['bugfix', 'feature', 'personal', 'testing', 'declined']);

const queue = [...readFileSync(sourcePath, 'utf8').matchAll(/patches\/([a-z0-9._-]+)\.patch/g)].map((m) => m[1]);
if (queue.length === 0) {
  console.error('assert-openchamber-ledger: no patches found in source.nix');
  process.exit(1);
}

let ledger;
try {
  ledger = JSON.parse(readFileSync(ledgerPath, 'utf8'));
} catch (error) {
  console.error(`assert-openchamber-ledger: ${ledgerPath} is not valid JSON: ${error.message}`);
  process.exit(1);
}

const records = ledger.patches ?? {};
const candidates = ledger.candidates ?? [];
const problems = [];

const patchesDir = join(packageDir, 'patches');
const patchFiles = readdirSync(patchesDir)
  .filter((name) => name.endsWith('.patch'))
  .map((name) => name.replace(/\.patch$/, ''));

let markerPatches = null;
try {
  markerPatches = new Set(
    JSON.parse(readFileSync(join(patchesDir, 'markers.json'), 'utf8')).patches.map((entry) => entry.patch.replace(/\.patch$/, '')),
  );
} catch (error) {
  problems.push(`markers.json is not readable: ${error.message}`);
}

for (const patch of patchFiles) {
  if (!queue.includes(patch)) {
    problems.push(`${patch}.patch exists in packages/openchamber/patches but is not in the queue`);
  }
}

for (const patch of queue) {
  if (!patchFiles.includes(patch)) {
    problems.push(`${patch}: queued but packages/openchamber/patches/${patch}.patch does not exist`);
  }
  if (markerPatches && !markerPatches.has(patch)) {
    problems.push(`${patch}: queued but has no entry in markers.json`);
  }
}

if (markerPatches) {
  for (const patch of markerPatches) {
    if (!queue.includes(patch)) {
      problems.push(`${patch}: markers.json entry exists but the patch is not in the queue`);
    }
  }
}

if (!Array.isArray(candidates)) {
  problems.push('"candidates" must be an array');
}

for (const patch of queue) {
  const record = records[patch];
  if (!record) {
    problems.push(`${patch}: no record in upstream.json`);
    continue;
  }
  if (!RELATIONSHIPS.has(record.relationship)) {
    problems.push(`${patch}: relationship '${record.relationship}' is not one of ${[...RELATIONSHIPS].join(', ')}`);
  }
  if (record.intent === undefined) {
    problems.push(`${patch}: no "intent" on the record`);
  } else if (!INTENTS.has(record.intent)) {
    problems.push(`${patch}: intent '${record.intent}' is not one of ${[...INTENTS].join(', ')}`);
  }
  if (!record.since) {
    problems.push(`${patch}: no "since" date on the record`);
  }
  if ((record.relationship === 'same' || record.relationship === 'pending') && !record.pr && !record.issue) {
    problems.push(`${patch}: relationship '${record.relationship}' needs a pr or an issue`);
  }
}

for (const patch of Object.keys(records)) {
  if (!queue.includes(patch)) {
    problems.push(`${patch}: record exists but the patch is not in the queue`);
  }
}

if (Array.isArray(candidates)) {
  for (const candidate of candidates) {
    const name = candidate?.name || '(unnamed candidate)';
    if (!candidate?.name) {
      problems.push('candidate: no name');
    }
    if (candidate?.intent === undefined) {
      problems.push(`${name}: candidate has no "intent"`);
    } else if (!INTENTS.has(candidate?.intent)) {
      problems.push(`${name}: candidate intent '${candidate.intent}' is not one of ${[...INTENTS].join(', ')}`);
    }
    if (!candidate?.note) {
      problems.push(`${name}: candidate needs a note saying what upstream work is owed`);
    }
    if (!candidate?.since) {
      problems.push(`${name}: candidate needs a "since" date`);
    }
  }
}

// A retired patch left the queue because upstream carries it (`same`, with the
// pull request and merge commit that did) or shipped a different design for the
// need (`alternative`). Its record says which, so the reason survives the file.
const retired = ledger.retired ?? [];
if (!Array.isArray(retired)) {
  problems.push('"retired" must be an array');
} else {
  for (const entry of retired) {
    const name = entry?.name || '(unnamed retired patch)';
    if (!entry?.name) problems.push('retired: no name');
    if (queue.includes(entry?.name)) problems.push(`${name}: retired but still in the queue`);
    if (patchFiles.includes(entry?.name)) problems.push(`${name}: retired but its patch file is still in packages/openchamber/patches`);
    if (entry?.relationship !== 'same' && entry?.relationship !== 'alternative') {
      problems.push(`${name}: a retired patch's relationship is same or alternative, not '${entry?.relationship}'`);
    }
    if (!entry?.pr && !entry?.mergedAs) problems.push(`${name}: a retired patch names the upstream pr or mergedAs that carries it`);
    if (!entry?.note) problems.push(`${name}: a retired patch needs a note with the content evidence`);
    if (!entry?.since) problems.push(`${name}: a retired patch needs a "since" date`);
  }
}

if (problems.length > 0) {
  console.error('OpenChamber patch ledger problems:');
  for (const problem of problems) console.error(`  ${problem}`);
  console.error('\nFix packages/openchamber/upstream.json or the patch directory, then run `just upstream <tag>` at the next base bump.');
  process.exit(1);
}

const candidateCount = Array.isArray(candidates) ? candidates.length : 0;
const retiredCount = Array.isArray(retired) ? retired.length : 0;
console.log(
  `OpenChamber patch ledger: ${queue.length} patches recorded, ${candidateCount} candidate${candidateCount === 1 ? '' : 's'}, ${retiredCount} retired`,
);
