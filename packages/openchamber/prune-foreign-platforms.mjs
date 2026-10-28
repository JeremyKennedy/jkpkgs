// Drop the dependency store entries the host cannot use.
//
// The fixed-output bun install runs with --os='*' --cpu='*' so its hash is
// the same on every platform, which leaves every platform's native optional
// dependency in node_modules/.bun. This applies the selection bun itself
// makes from each package's os/cpu/libc fields, then removes the symlinks
// that pointed at a dropped entry, so the runtime tree is host-only.
//
// Usage: bun prune-foreign-platforms.mjs <workspace root>
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(process.argv[2]);
const store = path.join(root, "node_modules", ".bun");
const host = {
  os: process.platform,
  cpu: process.arch,
  libc: process.platform === "linux" ? "glibc" : null,
};

// npm semantics: a plain entry allows, a "!" entry forbids, and a list of
// only "!" entries allows everything it does not name.
const allows = (list, value) => {
  if (!Array.isArray(list) || list.length === 0) return true;
  if (value === null) return true;
  if (list.includes(`!${value}`)) return false;
  const positive = list.filter((entry) => !entry.startsWith("!"));
  return positive.length === 0 || positive.includes(value);
};

// Store entries are "<name>@<version>[+<peer hash>]", with "/" in scoped
// names written as "+".
const packageName = (entry) => {
  const at = entry.lastIndexOf("@");
  return entry.slice(0, at > 0 ? at : entry.length).replace("+", "/");
};

const pruned = [];
for (const entry of fs.readdirSync(store)) {
  const manifest = path.join(store, entry, "node_modules", packageName(entry), "package.json");
  if (!fs.existsSync(manifest)) continue;
  const { os, cpu, libc } = JSON.parse(fs.readFileSync(manifest, "utf8"));
  if (allows(os, host.os) && allows(cpu, host.cpu) && allows(libc, host.libc)) continue;
  fs.rmSync(path.join(store, entry), { recursive: true, force: true });
  pruned.push(path.join(store, entry) + path.sep);
}

const unlinkDangling = (dir) => {
  for (const dirent of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, dirent.name);
    if (dirent.isSymbolicLink()) {
      const target = path.resolve(dir, fs.readlinkSync(file)) + path.sep;
      if (pruned.some((prefix) => target.startsWith(prefix))) fs.unlinkSync(file);
    } else if (dirent.isDirectory()) {
      unlinkDangling(file);
    }
  }
};
unlinkDangling(path.join(root, "node_modules"));
for (const workspace of fs.readdirSync(path.join(root, "packages"))) {
  const modules = path.join(root, "packages", workspace, "node_modules");
  if (fs.existsSync(modules)) unlinkDangling(modules);
}

console.log(`pruned ${pruned.length} foreign-platform store entries for ${host.os}-${host.cpu}`);
