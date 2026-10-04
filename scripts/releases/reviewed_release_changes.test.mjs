import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { collectReviewedReleaseChanges, generateReviewedReleaseNotes, requiresReviewedChange } from "./reviewed_release_changes.mjs";

const CLI = fileURLToPath(new URL("./generate_release_notes.mjs", import.meta.url));
const SOURCE = "lib/shared/search.dart";
const sha = (text) => createHash("sha256").update(text).digest("hex");

async function fixture(t) {
  const repoDir = await mkdtemp(path.join(os.tmpdir(), "reviewed-release-test-"));
  t.after(() => rm(repoDir, { recursive: true, force: true }));
  const git = (...args) => execFileSync("git", args, { cwd: repoDir, encoding: "utf8" }).trim();
  const put = async (file, contents) => {
    await mkdir(path.dirname(path.join(repoDir, file)), { recursive: true });
    await writeFile(path.join(repoDir, file), contents);
  };
  const commit = () => { git("add", "-A"); git("commit", "-qm", "Verified change"); return git("rev-parse", "HEAD"); };
  git("init", "-q"); git("config", "user.name", "Release test"); git("config", "user.email", "release-test@example.invalid");
  await put(SOURCE, "void search() {}\n");
  const fromCommit = commit();
  const content = "void search() { restoreKeyboardInput(); }\n";
  await put(SOURCE, content);
  const record = {
    schema_version: 1, id: "search-input", source: "ai", scope: "release", platforms: ["macos", "android"], module: "general",
    title: "Búsqueda disponible al volver a abrirla",
    summary: "El buscador vuelve a recibir lo que escribes después de cerrarlo y abrirlo otra vez.",
    items: ["Puedes cerrar y volver a abrir el buscador sin perder la posibilidad de escribir."],
    evidence: [{ path: SOURCE, sha256: sha(content) }],
  };
  const recordPath = "docs/releases/changes/search-input.json";
  const save = () => put(recordPath, JSON.stringify(record));
  const generate = (toCommit, platform = "android") => generateReviewedReleaseNotes({ repoDir, fromCommit, toCommit, platform });
  return { repoDir, git, put, commit, fromCommit, record, recordPath, save, generate };
}

test("publication copies reviewed behavior verbatim without provider credentials or speculative benefits", async (t) => {
  const f = await fixture(t); await f.save(); const toCommit = f.commit();
  const notes = f.generate(toCommit).release_notes;
  assert.equal(notes.title, f.record.title);
  assert.deepEqual(notes.modules[0].items, f.record.items);
  assert.equal(notes.from_commit, f.fromCommit); assert.equal(notes.to_commit, toCommit);
  assert.deepEqual(f.generate(toCommit, "macos").release_notes, notes);
  assert.doesNotMatch(JSON.stringify(notes), /presupuestos|rendimiento|navegación/u);
  const output = path.join(f.repoDir, "output.json");
  const result = spawnSync(process.execPath, [CLI, "--from-commit", f.fromCommit, "--to-commit", toCommit,
    "--platform", "android", "--output", output], { cwd: f.repoDir, encoding: "utf8",
    env: { ...process.env, GEMINI_RELEASE_API_KEY: "", OPENAI_API_KEY: "", HTTPS_PROXY: "http://127.0.0.1:1" } });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /provider: reviewed-change-records/u);
  assert.deepEqual(JSON.parse(await readFile(output, "utf8")), { release_notes: notes });
});

test("Debug-only changes and other platforms cannot turn into Release benefits", async (t) => {
  const f = await fixture(t);
  f.record.scope = "debug"; f.record.title = ""; f.record.summary = ""; f.record.items = [];
  await f.save(); let to = f.commit();
  assert.equal(f.generate(to).release_notes.title, "Actualización de mantenimiento");
  assert.deepEqual(f.generate(to).release_notes.modules[0].items,
    ["Esta entrega no incorpora cambios visibles en las funciones de la aplicación."]);
  // Adding an advertised benefit to a Debug record fails, even with valid hashes.
  f.record.items = ["Ahora puedes crear presupuestos en el taller sin perder datos."];
  await f.save(); to = f.commit();
  assert.throws(() => f.generate(to), /Debug\/internal/u);
});

test("platform-specific reviewed changes are excluded from other platform notes", async (t) => {
  const f = await fixture(t); f.record.platforms = ["android"]; await f.save(); const to = f.commit();
  assert.equal(f.generate(to, "android").release_notes.title, f.record.title);
  assert.equal(f.generate(to, "windows").release_notes.title, "Actualización de mantenimiento");
  assert.throws(() => f.generate(to, "unknown"), /explicit release platform/u);
});

test("missing review, stale source and fabricated evidence block publication with no fallback file", async (t) => {
  const f = await fixture(t); let to = f.commit();
  assert.throws(() => f.generate(to), /Missing reviewed release changes/u);
  await f.save(); to = f.commit();
  assert.equal(f.generate(to).source, "ai");
  await f.put(SOURCE, "void search() { unrelatedBehavior(); }\n"); to = f.commit();
  assert.throws(() => f.generate(to), /needs review after its source changed/u);
  const output = path.join(f.repoDir, "invalid.json");
  const result = spawnSync(process.execPath, [CLI, "--from-commit", f.fromCommit, "--to-commit", to,
    "--platform", "android", "--output", output], { cwd: f.repoDir, encoding: "utf8" });
  assert.notEqual(result.status, 0); assert.equal(existsSync(output), false);
  f.record.evidence[0].path = "lib/not-in-range.dart"; await f.save(); to = f.commit();
  assert.throws(() => f.generate(to), /outside the exact source changes/u);
});

test("pre-commit validation reads staged source rather than an unstaged replacement", async (t) => {
  const f = await fixture(t); await f.save(); f.git("add", "-A");
  collectReviewedReleaseChanges({ repoDir: f.repoDir, fromCommit: f.fromCommit, index: true });
  await f.put(SOURCE, "void search() { newerSource(); }\n");
  collectReviewedReleaseChanges({ repoDir: f.repoDir, fromCommit: f.fromCommit, index: true });
  f.git("add", SOURCE);
  assert.throws(() => collectReviewedReleaseChanges({ repoDir: f.repoDir, fromCommit: f.fromCommit, index: true }), /needs review/u);
});

test("already-published records are immutable and cannot advertise changes from another range", async (t) => {
  const f = await fixture(t); await f.save(); const published = f.commit();
  f.record.items = ["Puedes usar el buscador al volver a abrirlo."]; await f.save(); const to = f.commit();
  assert.throws(() => generateReviewedReleaseNotes({ repoDir: f.repoDir, fromCommit: published, toCommit: to, platform: "macos" }), /immutable/u);
});

test("module ownership, missing coverage and generic filler require a reviewed correction", async (t) => {
  const f = await fixture(t); f.record.module = "workshop"; await f.save(); let to = f.commit();
  assert.throws(() => f.generate(to), /source owner/u);
  f.record.module = "general"; f.record.items = ["Mejoras generales"]; await f.save(); to = f.commit();
  assert.throws(() => f.generate(to), /Generic filler/u);
  f.record.items = ["Puedes escribir de nuevo al volver a abrir el buscador."]; await f.save();
  await f.put("lib/shared/another.dart", "void another() {}\n"); to = f.commit();
  assert.throws(() => f.generate(to), /Missing reviewed release changes.*another/u);
});

test("symlinks and binary source cannot masquerade as reviewed application changes", async (t) => {
  const f = await fixture(t); await rm(path.join(f.repoDir, SOURCE)); await symlink("other.dart", path.join(f.repoDir, SOURCE));
  f.record.evidence[0].sha256 = sha("other.dart"); await f.save(); let to = f.commit();
  assert.throws(() => f.generate(to), /regular tracked source/u);
  await rm(path.join(f.repoDir, SOURCE)); await f.put(SOURCE, Buffer.from([1, 0, 2]));
  f.record.evidence[0].sha256 = sha(Buffer.from([1, 0, 2])); await f.save(); to = f.commit();
  assert.throws(() => f.generate(to), /Binary content/u);
});

test("the shared public core and the HTML storefront need their own review, not just the lib/ reexport", () => {
  assert.equal(requiresReviewedChange("packages/vinabike_public_core/lib/shared/models/product.dart"), true);
  assert.equal(requiresReviewedChange("services/storefront_html/lib/src/storefront_handler.dart"), true);
  assert.equal(requiresReviewedChange("services/storefront_html/Dockerfile"), true);
  assert.equal(requiresReviewedChange("packages/vinabike_public_core/test/core_runs_without_flutter_test.dart"), false);
  assert.equal(requiresReviewedChange("services/storefront_html/test/storefront_handler_test.dart"), false);
  assert.equal(requiresReviewedChange("packages/excel_localized/lib/excel.dart"), false);
});
