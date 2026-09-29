import { execFile } from "node:child_process";
import { readFile, stat } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const MARKERS = [
  "package.json",
  "Cargo.toml",
  "go.mod",
  "pyproject.toml",
  "composer.json",
  "Gemfile",
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "mix.exs",
];

async function exists(file) {
  try {
    await stat(file);
    return true;
  } catch {
    return false;
  }
}

async function readName(file, marker, dir) {
  const fallback = path.basename(dir);
  try {
    const text = await readFile(file, "utf8");
    if (marker === "package.json" || marker === "composer.json") {
      const name = JSON.parse(text).name;
      return typeof name === "string" && name ? name : fallback;
    }
    if (marker === "go.mod") {
      return text.match(/^module\s+(\S+)/m)?.[1] ?? fallback;
    }
    if (marker === "Cargo.toml" || marker === "pyproject.toml") {
      return text.match(/^name\s*=\s*"([^"]+)"/m)?.[1] ?? fallback;
    }
  } catch {
    return fallback;
  }
  return fallback;
}

async function gitBranch(dir) {
  try {
    const { stdout } = await execFileAsync("git", ["-C", dir, "rev-parse", "--abbrev-ref", "HEAD"], {
      timeout: 2000,
    });
    const branch = stdout.trim();
    if (!branch) return null;
    return branch === "HEAD" ? "detached" : branch;
  } catch {
    return null;
  }
}

export function isRuntimeDir(cwd) {
  const normalized = path.resolve(cwd).split(path.sep).join("/");
  return (
    normalized.includes("/.gradle/") ||
    normalized.includes("/.m2/") ||
    normalized.includes("/node_modules/") ||
    normalized.includes("/Library/Containers/") ||
    normalized.includes("/Library/Caches/") ||
    normalized.includes("/kotlin/daemon")
  );
}

export async function detectProject(cwd) {
  if (!cwd || isRuntimeDir(cwd)) return null;
  let dir = path.resolve(cwd);
  const root = path.parse(dir).root;

  while (true) {
    for (const marker of MARKERS) {
      const file = path.join(dir, marker);
      if (!(await exists(file))) continue;
      return {
        name: await readName(file, marker, dir),
        root: dir,
        branch: await gitBranch(dir),
      };
    }
    if (dir === root) break;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }

  const resolved = path.resolve(cwd);
  if (resolved === homedir()) return null;
  return {
    name: path.basename(resolved),
    root: resolved,
    branch: await gitBranch(cwd),
  };
}
