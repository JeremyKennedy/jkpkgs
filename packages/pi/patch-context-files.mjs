#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const packageRoot = process.argv[2];
if (!packageRoot) {
  console.error("usage: patch-context-files.mjs <pi-coding-agent-package-root>");
  process.exit(2);
}

const resourceLoader = join(packageRoot, "dist/core/resource-loader.js");
let text = readFileSync(resourceLoader, "utf8");

const oldFunction = `function loadContextFileFromDir(dir) {
    const candidates = ["AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD"];
    for (const filename of candidates) {
        const filePath = join(dir, filename);
        if (existsSync(filePath)) {
            try {
                return {
                    path: filePath,
                    content: readFileSync(filePath, "utf-8"),
                };
            }
            catch (error) {
                console.error(chalk.yellow(\`Warning: Could not read \${filePath}: \${error}\`));
            }
        }
    }
    return null;
}`;

const newFunction = `function loadContextFilesFromDir(dir) {
    const candidates = ["AGENTS.md", "AGENTS.MD", "CLAUDE.md", "CLAUDE.MD"];
    const contextFiles = [];
    for (const filename of candidates) {
        const filePath = join(dir, filename);
        if (existsSync(filePath)) {
            try {
                contextFiles.push({
                    path: filePath,
                    content: readFileSync(filePath, "utf-8"),
                });
            }
            catch (error) {
                console.error(chalk.yellow(\`Warning: Could not read \${filePath}: \${error}\`));
            }
        }
    }
    return contextFiles;
}`;

const oldGlobal = `    const globalContext = loadContextFileFromDir(resolvedAgentDir);
    if (globalContext) {
        contextFiles.push(globalContext);
        seenPaths.add(globalContext.path);
    }`;
const newGlobal = `    for (const globalContext of loadContextFilesFromDir(resolvedAgentDir)) {
        if (!seenPaths.has(globalContext.path)) {
            contextFiles.push(globalContext);
            seenPaths.add(globalContext.path);
        }
    }`;

const oldAncestor = `        const contextFile = loadContextFileFromDir(currentDir);
        if (contextFile && !seenPaths.has(contextFile.path)) {
            ancestorContextFiles.unshift(contextFile);
            seenPaths.add(contextFile.path);
        }`;
const newAncestor = `        const dirContextFiles = loadContextFilesFromDir(currentDir).filter((contextFile) => !seenPaths.has(contextFile.path));
        if (dirContextFiles.length > 0) {
            ancestorContextFiles.unshift(...dirContextFiles);
            for (const contextFile of dirContextFiles) {
                seenPaths.add(contextFile.path);
            }
        }`;

function replaceOnce(haystack, needle, replacement, label) {
  const count = haystack.split(needle).length - 1;
  if (count !== 1) {
    throw new Error(`expected exactly one ${label} match, found ${count}`);
  }
  return haystack.replace(needle, replacement);
}

text = replaceOnce(text, oldFunction, newFunction, "context loader function");
text = replaceOnce(text, oldGlobal, newGlobal, "global context load block");
text = replaceOnce(text, oldAncestor, newAncestor, "ancestor context load block");
writeFileSync(resourceLoader, text);
