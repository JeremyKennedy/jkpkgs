#!/usr/bin/env node
// Offline gate for the OpenChamber patch ledger.
//
// Every patch in the queue must have a record in packages/openchamber/upstream.json
// saying what it is to upstream, and every record must belong to a queued patch.
// This runs inside `just check`, so a patch cannot be added, dropped or
// re-expressed without saying what it is and whether upstream has it.
//
// It does not talk to the network. Whether a release already contains a patch is
// `just upstream <tag>`, run at a base bump.

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const packageDir = join(repoRoot, 'packages', 'openchamber');
const ledgerPath = join(packageDir, 'upstream.json');
const sourcePath = join(packageDir, 'source.nix');

const RELATIONSHIPS = new Set(['same', 'alternative', 'partial', 'pending', 'none']);

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
const problems = [];

for (const patch of queue) {
  const record = records[patch];
  if (!record) {
    problems.push(`${patch}: no record in upstream.json`);
    continue;
  }
  if (!RELATIONSHIPS.has(record.relationship)) {
    problems.push(`${patch}: relationship '${record.relationship}' is not one of ${[...RELATIONSHIPS].join(', ')}`);
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

if (problems.length > 0) {
  console.error('OpenChamber patch ledger problems:');
  for (const problem of problems) console.error(`  ${problem}`);
  console.error('\nFix packages/openchamber/upstream.json, then run `just upstream <tag>` at the next base bump.');
  process.exit(1);
}

console.log(`OpenChamber patch ledger: ${queue.length} patches recorded`);
