#!/usr/bin/env node
// Offline gate: a patch edits another patch's work only when it says so.
//
// The queue applies in order, so a later patch may legitimately rewrite lines
// an earlier one added: attention-row-parity reworks instance-attention's
// files, and source.nix says so. The failure this catches is the silent kind.
// session-entry-position once carried lint cleanups of command-code.ts and the
// Gitea reference search, rewriting 64 and 74 lines that commandcode-quota and
// gitea-references-across had added. The queue still built the right bytes,
// but each of those patches no longer described its own file, and a base bump
// had to port the cleanup through the wrong patch.
//
// The rule: when a patch removes a line that an earlier patch added, in the
// same file, the earlier patch must be listed in the later patch's `follows`
// in packages/openchamber/upstream.json, unless the file is one of the shared
// settings files below. Otherwise the hunk belongs in the earlier patch.
//
// Lines are compared trimmed, and only lines with at least MIN_LINE_LENGTH
// characters and a letter count, so a shared `});` is not an edit.
//
// What it does not catch: a patch that only adds lines to another patch's
// file. Those read as the later patch's own work, which they usually are.

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const packageDir = join(repoRoot, 'packages', 'openchamber');
const patchesDir = join(packageDir, 'patches');

const MIN_LINE_LENGTH = 10;

// Files every settings patch extends: the registries, the sanitizer, the
// settings search and page, and the settings strings of each locale. Settings
// patches insert entries side by side here and sometimes reflow a neighbour's
// line to fit, so an edit here is not ownership. Listed by name on purpose:
// a new shared file is a decision, not a pattern match.
const SHARED_FILES = new Set([
  'packages/ui/src/components/sections/openchamber/ChatSettings.tsx',
  'packages/ui/src/components/sections/openchamber/chatSettingsTabs.ts',
  'packages/ui/src/lib/settings/registry.ts',
  'packages/ui/src/lib/settings/search.ts',
  'packages/vscode/src/settings-registry.json',
  'packages/web/server/lib/settings/settings-helpers.test.js',
  'packages/web/server/lib/settings/settings-helpers.ts',
  'packages/web/server/lib/settings/settings-registry.json',
  'packages/ui/src/lib/i18n/messages/ar.settings.ts',
  'packages/ui/src/lib/i18n/messages/de.settings.ts',
  'packages/ui/src/lib/i18n/messages/en.settings.ts',
  'packages/ui/src/lib/i18n/messages/es.settings.ts',
  'packages/ui/src/lib/i18n/messages/fr.settings.ts',
  'packages/ui/src/lib/i18n/messages/he.settings.ts',
  'packages/ui/src/lib/i18n/messages/ja.settings.ts',
  'packages/ui/src/lib/i18n/messages/ko.settings.ts',
  'packages/ui/src/lib/i18n/messages/nl.settings.ts',
  'packages/ui/src/lib/i18n/messages/pl.settings.ts',
  'packages/ui/src/lib/i18n/messages/pt-BR.settings.ts',
  'packages/ui/src/lib/i18n/messages/tr.settings.ts',
  'packages/ui/src/lib/i18n/messages/uk.settings.ts',
  'packages/ui/src/lib/i18n/messages/zh-CN.settings.ts',
  'packages/ui/src/lib/i18n/messages/zh-TW.settings.ts',
]);

const queue = [...readFileSync(join(packageDir, 'source.nix'), 'utf8').matchAll(/patches\/([a-z0-9._-]+)\.patch/g)].map(
  (m) => m[1],
);
const records = JSON.parse(readFileSync(join(packageDir, 'upstream.json'), 'utf8')).patches ?? {};

const significant = (line) => line.length >= MIN_LINE_LENGTH && /[A-Za-z]/.test(line);

// Per patch: file -> { added: Set of lines, removed: Map line -> count }.
// Added lines are filed under the new path and removed lines under the old
// one, so a patch that renames another patch's file and edits it is still
// compared against the path the earlier patch added those lines to.
const parsePatch = (name) => {
  const files = new Map();
  const entry = (path) => {
    if (!files.has(path)) files.set(path, { added: new Set(), removed: new Map() });
    return files.get(path);
  };
  let oldFile = null;
  let newFile = null;
  let inHunk = false;
  for (const line of readFileSync(join(patchesDir, `${name}.patch`), 'utf8').split('\n')) {
    if (line.startsWith('diff --git ')) {
      const match = /^diff --git a\/(.+) b\/(.+)$/.exec(line);
      oldFile = entry(match[1]);
      newFile = entry(match[2]);
      inHunk = false;
      continue;
    }
    if (line.startsWith('@@')) {
      inHunk = true;
      continue;
    }
    // Before the first hunk, `---` and `+++` are the file headers; inside a
    // hunk they are content lines that start with `--` or `++`.
    if (!inHunk || !newFile) continue;
    const text = line.slice(1).trim();
    if (!significant(text)) continue;
    if (line[0] === '+') newFile.added.add(text);
    else if (line[0] === '-') oldFile.removed.set(text, (oldFile.removed.get(text) ?? 0) + 1);
  }
  return files;
};

const problems = [];
const parsed = new Map(queue.map((name) => [name, parsePatch(name)]));

for (const [index, name] of queue.entries()) {
  const follows = records[name]?.follows ?? [];
  if (!Array.isArray(follows)) {
    problems.push(`${name}: "follows" must be an array of patch names`);
    continue;
  }
  for (const earlier of follows) {
    const position = queue.indexOf(earlier);
    if (position === -1) problems.push(`${name}: follows '${earlier}', which is not in the queue`);
    else if (position >= index) problems.push(`${name}: follows '${earlier}', which comes after it in source.nix`);
  }

  // edits: earlier patch -> file -> number of removed lines that patch added there.
  const edits = new Map();
  for (const [file, { removed }] of parsed.get(name)) {
    if (SHARED_FILES.has(file)) continue;
    for (const [text, count] of removed) {
      // The most recent earlier patch that added this line is the one edited.
      for (let k = index - 1; k >= 0; k -= 1) {
        if (parsed.get(queue[k]).get(file)?.added.has(text)) {
          const byFile = edits.get(queue[k]) ?? new Map();
          byFile.set(file, (byFile.get(file) ?? 0) + count);
          edits.set(queue[k], byFile);
          break;
        }
      }
    }
  }
  for (const [earlier, byFile] of edits) {
    if (follows.includes(earlier)) continue;
    const total = [...byFile.values()].reduce((sum, count) => sum + count, 0);
    const files = [...byFile].map(([file, count]) => `\n      ${count} in ${file}`).join('');
    problems.push(`${name} rewrites ${total} line${total === 1 ? '' : 's'} that ${earlier} adds:${files}`);
  }
}

if (problems.length > 0) {
  console.error('OpenChamber patch overlap problems:');
  for (const problem of problems) console.error(`  ${problem}`);
  console.error(
    '\nA hunk that changes an earlier patch\'s own lines belongs in that patch: move it there and re-export both.' +
      '\nWhen the later patch really builds on the earlier one, list it in the later record\'s "follows" in' +
      ' packages/openchamber/upstream.json.',
  );
  process.exit(1);
}

const declared = queue.reduce((sum, name) => sum + (records[name]?.follows?.length ?? 0), 0);
console.log(`OpenChamber patch overlap: ${queue.length} patches, ${declared} declared follows, no undeclared edits`);
