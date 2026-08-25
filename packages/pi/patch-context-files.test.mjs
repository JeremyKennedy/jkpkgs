#!/usr/bin/env node
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const source = `const sep = "/";
function stripBom(text) { return text; }
function canonicalizePath(p) { return p; }
function findGitPaths(cwd) { return null; }
function loadContextFileFromDir(dir) {
    const candidates = ["AGENTS.override.md", "AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD"];
    for (const filename of candidates) {
        const filePath = join(dir, filename);
        if (existsSync(filePath)) {
            try {
                if (!statSync(filePath).isFile()) {
                    continue;
                }
                return {
                    path: filePath,
                    content: stripBom(readFileSync(filePath, "utf-8")),
                };
            }
            catch (error) {
                console.error(chalk.yellow(\`Warning: Could not read \${filePath}: \${error}\`));
            }
        }
    }
    return null;
}
function findShadowedContextFile(cwd) {
    const gitPaths = findGitPaths(cwd);
    if (!gitPaths)
        return undefined;
    const commonGitDir = canonicalizePath(gitPaths.commonGitDir);
    const worktreeRoot = canonicalizePath(gitPaths.repoDir);
    const mainRepoRoot = dirname(commonGitDir);
    if (!worktreeRoot.startsWith(\`\${mainRepoRoot}\${sep}\`))
        return undefined;
    if (canonicalizePath(join(mainRepoRoot, ".git")) !== commonGitDir)
        return undefined;
    const worktreeContextFile = loadContextFileFromDir(worktreeRoot);
    return worktreeContextFile ? join(mainRepoRoot, basename(worktreeContextFile.path)) : undefined;
}
export function loadProjectContextFiles(options) {
    const resolvedCwd = resolvePath(options.cwd);
    const resolvedAgentDir = resolvePath(options.agentDir);
    const contextFiles = [];
    const seenPaths = new Set();
    const globalContext = loadContextFileFromDir(resolvedAgentDir);
    if (globalContext) {
        contextFiles.push(globalContext);
        seenPaths.add(globalContext.path);
    }
    const ancestorContextFiles = [];
    const shadowedContextFile = findShadowedContextFile(resolvedCwd);
    let currentDir = resolvedCwd;
    while (true) {
        const contextFile = loadContextFileFromDir(currentDir);
        const isShadowed = shadowedContextFile !== undefined && canonicalizePath(contextFile?.path ?? "") === shadowedContextFile;
        if (contextFile && !isShadowed && !seenPaths.has(contextFile.path)) {
            ancestorContextFiles.unshift(contextFile);
            seenPaths.add(contextFile.path);
        }
        const parentDir = dirname(currentDir);
        if (parentDir === currentDir)
            break;
        currentDir = parentDir;
    }
    contextFiles.push(...ancestorContextFiles);
    return contextFiles;
}
`;

const workspace = mkdtempSync(join(tmpdir(), "pi-context-patch-"));
try {
  const packageRoot = join(workspace, "node_modules", "@earendil-works", "pi-coding-agent");
  const resourceLoader = join(packageRoot, "dist", "core", "resource-loader.js");
  mkdirSync(join(packageRoot, "dist", "core"), { recursive: true });
  writeFileSync(resourceLoader, source);

  execFileSync(process.execPath, ["patch-context-files.mjs", packageRoot], {
    cwd: import.meta.dirname,
    stdio: "inherit",
  });

  const patched = readFileSync(resourceLoader, "utf8");
  assert.match(patched, /function loadContextFilesFromDir\(dir\)/);
  assert.match(patched, /function loadContextFileFromDir\(dir\)/);
  assert.match(patched, /if \(!statSync\(filePath\)\.isFile\(\)\)/);
} finally {
  rmSync(workspace, { recursive: true, force: true });
}
