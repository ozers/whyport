import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { detectProject } from "../src/project.js";

test("detectProject reads the nearest package name and walks up from a subdirectory", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "whyport-"));
  const nested = path.join(root, "services", "api");
  await mkdir(nested, { recursive: true });
  await writeFile(path.join(root, "package.json"), JSON.stringify({ name: "shop" }));
  try {
    const project = await detectProject(nested);
    assert.equal(project.name, "shop");
    assert.equal(project.root, root);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("detectProject ignores daemon and container directories", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "whyport-"));
  const daemon = path.join(root, ".gradle", "daemon", "9.6.1");
  await mkdir(daemon, { recursive: true });
  await writeFile(path.join(daemon, "package.json"), JSON.stringify({ name: "not-a-project" }));
  try {
    assert.equal(await detectProject(daemon), null);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("detectProject reads go modules and cargo package names", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "whyport-"));
  await writeFile(path.join(root, "go.mod"), "module example.com/api\n\ngo 1.22\n");
  const cargo = await mkdtemp(path.join(tmpdir(), "whyport-"));
  await writeFile(path.join(cargo, "Cargo.toml"), "[package]\nname = \"porter\"\nversion = \"0.1.0\"\n");
  try {
    assert.equal((await detectProject(root)).name, "example.com/api");
    assert.equal((await detectProject(cargo)).name, "porter");
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(cargo, { recursive: true, force: true });
  }
});
