import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  collectReleaseInventory,
  isBinaryReleasePath,
  isGeneratedReleasePath,
  isSensitiveReleasePath,
  isPlainUserText,
  moduleForReleasePath,
  RELEASE_NOTE_MODULES,
  validateReleaseNotes,
} from "./generate_release_notes.mjs";

const PREFIX = "docs/releases/changes/";
const PLATFORMS = ["macos", "windows", "android", "web", "ios"];
const SCOPES = ["release", "debug", "internal"];

function git(repoDir, args, encoding = "utf8") {
  return execFileSync("git", args, { cwd: repoDir, encoding, maxBuffer: 8 * 1024 * 1024 });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function keys(value, names) {
  return value && typeof value === "object" && !Array.isArray(value) &&
    Object.keys(value).sort().join(",") === [...names].sort().join(",");
}

function safePath(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 240 &&
    !value.includes("\\") && !/[\x00-\x1f\x7f]/u.test(value) &&
    !value.split("/").some((part) => !part || part === "." || part === "..");
}

// Since 2026-10-04 the public product rules live in a pure Dart package the
// apps compile in, and the HTML storefront serves them: a change there leaves
// the one-line reexport in lib/ untouched, so it must be covered on its own.
export function requiresReviewedChange(file) {
  return file === "pubspec.yaml" ||
    (/^(?:lib|android|macos|windows|ios|scripts|\.github\/workflows|packages\/vinabike_public_core|services\/storefront_html)\//u.test(file) &&
      !/(?:^|\/)(?:tests?|fixtures?|mocks?)(?:\/|$)|\.test\.mjs$/u.test(file) &&
      !isGeneratedReleasePath(file) && !isSensitiveReleasePath(file) && !isBinaryReleasePath(file));
}

function indexedChanges(repoDir, fromCommit) {
  git(repoDir, ["cat-file", "-e", `${fromCommit}^{commit}`]);
  git(repoDir, ["merge-base", "--is-ancestor", fromCommit, "HEAD"]);
  const tokens = git(repoDir, ["diff", "--cached", "--name-status", "--no-renames", "-z", fromCommit]).split("\0");
  tokens.pop();
  const changes = [];
  for (let i = 0; i < tokens.length; i += 2) {
    changes.push({ status_code: tokens[i], path: tokens[i + 1], module_id: moduleForReleasePath(tokens[i + 1]) });
  }
  return changes;
}

function sourceBlob(repoDir, file, fromCommit, toCommit, index, deleted) {
  const revision = deleted ? fromCommit : toCommit;
  const listing = index && !deleted ? git(repoDir, ["ls-files", "--stage", "--", file]) :
    git(repoDir, ["ls-tree", revision, "--", file]);
  assert(/^100(?:644|755) /u.test(listing), "Release evidence must be a regular tracked source file.");
  const ref = deleted ? `${fromCommit}:${file}` : index ? `:${file}` : `${toCommit}:${file}`;
  return git(repoDir, ["show", ref], "buffer");
}

export function collectReviewedReleaseChanges({ repoDir = process.cwd(), fromCommit, toCommit, index = false }) {
  assert(/^[a-f0-9]{40}$/u.test(fromCommit ?? ""), "An exact release baseline is required.");
  const inventory = index ? null : collectReleaseInventory({ repoDir, fromCommit, toCommit });
  const changes = index ? indexedChanges(repoDir, fromCommit) : inventory.all_changes;
  const changed = new Map(changes.map((entry) => [entry.path, entry]));
  const recordFiles = changes.filter((entry) => entry.path.startsWith(PREFIX) && entry.path.endsWith(".json"));
  assert(recordFiles.length <= 100, "The release has too many change records; review the release boundary.");
  const records = [];
  const ids = new Set();
  const covered = new Set();
  for (const entry of recordFiles) {
    assert(entry.status_code === "A", "Published change records are immutable; add a new record.");
    const bytes = sourceBlob(repoDir, entry.path, fromCommit, toCommit, index, false);
    assert(bytes.length <= 32768 && !bytes.includes(0), "A change record is outside its text boundary.");
    const record = JSON.parse(bytes.toString("utf8"));
    assert(keys(record, ["schema_version", "id", "source", "scope", "platforms", "module", "title", "summary", "items", "evidence"]), "A change record has an invalid shape.");
    assert(record.schema_version === 1 && record.source === "ai", "Change records must identify their reviewed AI authoring source.");
    assert(/^[a-z][a-z0-9-]{2,79}$/u.test(record.id ?? "") && !ids.has(record.id), "Change record IDs must be unique.");
    ids.add(record.id);
    assert(SCOPES.includes(record.scope) && Object.hasOwn(RELEASE_NOTE_MODULES, record.module), "A change record has an unsupported scope or module.");
    assert(Array.isArray(record.platforms) && record.platforms.length > 0 &&
      new Set(record.platforms).size === record.platforms.length && record.platforms.every((p) => PLATFORMS.includes(p)), "A change record has invalid platforms.");
    assert(Array.isArray(record.items) && record.items.length <= 3, "A change record has too many items.");
    if (record.scope === "release") {
      assert(isPlainUserText(record.title) && record.title.length <= 80 &&
        isPlainUserText(record.summary) && record.summary.length <= 280 && record.items.length > 0 &&
        record.items.every((item) => isPlainUserText(item) && item.length <= 160), "Release changes need concrete, reviewed plain-language notes.");
      assert(record.items.every((item) => !/^(?:se (?:realizaron|hicieron|implementaron) )?(?:mejoras|ajustes|optimizaciones)(?: generales| internos| de estabilidad)?[. ]*$/iu.test(item)), "Generic filler is not a release change.");
    } else {
      assert(record.title === "" && record.summary === "" && record.items.length === 0, "Debug/internal changes must not advertise user-facing benefits.");
    }
    assert(Array.isArray(record.evidence) && record.evidence.length > 0 && record.evidence.length <= 200, "A change record needs bounded source evidence.");
    const seenPaths = new Set();
    for (const evidence of record.evidence) {
      assert(keys(evidence, ["path", "sha256"]) && safePath(evidence.path) &&
        !seenPaths.has(evidence.path) && /^[a-f0-9]{64}$/u.test(evidence.sha256 ?? ""), "A change record has invalid source evidence.");
      seenPaths.add(evidence.path);
      const change = changed.get(evidence.path);
      assert(change && !evidence.path.startsWith(PREFIX) && !isSensitiveReleasePath(evidence.path) &&
        !isGeneratedReleasePath(evidence.path) && !isBinaryReleasePath(evidence.path), "A change record cites a file outside the exact source changes.");
      const deleted = change.status_code === "D";
      const sourceBytes = sourceBlob(repoDir, evidence.path, fromCommit, toCommit, index, deleted);
      assert(!sourceBytes.includes(0), "Binary content cannot establish a reviewed release change.");
      assert(createHash("sha256").update(sourceBytes).digest("hex") === evidence.sha256,
        `Change record ${record.id} needs review after its source changed: ${evidence.path}`);
      covered.add(evidence.path);
    }
    assert(record.evidence.some((e) => requiresReviewedChange(e.path)), "Documentation or tests alone cannot establish a shipped behavior.");
    if (record.scope === "release") assert(record.evidence.some((e) =>
      requiresReviewedChange(e.path) && moduleForReleasePath(e.path) === record.module), "A release module needs evidence from its source owner.");
    records.push({ ...record, record_path: entry.path });
  }
  const missing = changes.filter((entry) => requiresReviewedChange(entry.path) && !covered.has(entry.path)).map((entry) => entry.path);
  assert(missing.length === 0, `Missing reviewed release changes for: ${missing.join(", ")}`);
  assert(records.length > 0, "No reviewed release changes exist in this range; do not infer benefits from filenames.");
  return { inventory: inventory ?? { from_commit: fromCommit, to_commit: git(repoDir, ["rev-parse", "HEAD"]).trim(), all_changes: changes }, records };
}

export function assembleReviewedReleaseNotes({ inventory, records, platform }) {
  assert(PLATFORMS.includes(platform), "An explicit release platform is required.");
  const visible = records.filter((record) => record.scope === "release" && record.platforms.includes(platform));
  const groups = new Map();
  for (const record of visible) {
    const group = groups.get(record.module) ?? { id: record.module, label: RELEASE_NOTE_MODULES[record.module], items: [], evidence_paths: [] };
    group.items.push(...record.items);
    group.evidence_paths.push(...record.evidence.map((e) => e.path), record.record_path);
    groups.set(record.module, group);
  }
  assert(groups.size <= 5, "Curate the release into at most five modules; do not silently drop changes.");
  const modules = [...groups.values()].map((group) => {
    assert(group.items.length <= 3 && new Set(group.items).size === group.items.length, "Curate each module into at most three distinct release items.");
    const evidence = [...new Set(group.evidence_paths)];
    const primary = evidence.find((p) => moduleForReleasePath(p) === group.id);
    assert(primary, "A release module needs source evidence from its owner.");
    return { ...group, evidence_paths: [primary, ...evidence.filter((p) => p !== primary)].slice(0, 12) };
  });
  if (modules.length === 0) {
    modules.push({ id: "general", label: RELEASE_NOTE_MODULES.general,
      items: ["Esta entrega no incorpora cambios visibles en las funciones de la aplicación."],
      evidence_paths: records.map((record) => record.record_path).slice(0, 12) });
  }
  const notes = {
    schema_version: 1, locale: "es-CL", source: "ai",
    from_commit: inventory.from_commit, to_commit: inventory.to_commit,
    title: visible.length === 1 ? visible[0].title : visible.length ? "Novedades de esta actualización" : "Actualización de mantenimiento",
    summary: visible.length === 1 ? visible[0].summary : visible.length ? visible.map((record) => record.title).join(". ") : "Esta entrega no incorpora novedades visibles en esta plataforma.",
    modules,
  };
  // The text is copied verbatim from the committed review. No model can add a
  // claim, rewrite a benefit, or turn a Debug-only change into Release behavior.
  const fullInventory = { ...inventory, ai_changes: inventory.all_changes.filter((e) =>
    !e.binary && !isBinaryReleasePath(e.path) && !isSensitiveReleasePath(e.path) && !isGeneratedReleasePath(e.path)) };
  validateReleaseNotes(notes, { inventory: fullInventory, source: "ai" });
  return { source: "ai", provider: "reviewed-change-records", model: null, reason: null, inventory, release_notes: notes };
}

export function generateReviewedReleaseNotes({ repoDir = process.cwd(), fromCommit, toCommit, platform }) {
  return assembleReviewedReleaseNotes({ ...collectReviewedReleaseChanges({ repoDir, fromCommit, toCommit }), platform });
}
