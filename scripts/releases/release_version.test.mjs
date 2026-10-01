import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { assertForwardReleaseVersion, compareVersions, desktopPublicationFromManifest, planReleaseVersion, prepareReleaseVersion } from "./release_version.mjs";

const old = "a".repeat(40), next = "b".repeat(40);
const plan = (args = {}) => planReleaseVersion({ currentVersion: "1.0.3", headCommit: next, dirty: false,
  publications: [{ version: "1.0.3", commit: old }], ...args });

test("new source advances the visible patch, even when only build counters previously advanced", () => {
  assert.equal(plan().version, "1.0.4");
  assert.equal(plan({ currentVersion: "1.0.4", publications: [{ version: "1.0.4", commit: old }] }).version, "1.0.5");
  assert.equal(plan({ dirty: true, headCommit: old }).version, "1.0.4");
  assert.equal(plan({ currentVersion: "1.1.0" }).version, "1.1.0");
  assert.equal(compareVersions("1.0.10", "1.0.9"), 1);
});

test("same-commit retries and a lagging paired platform keep the prepared visible version", () => {
  assert.deepEqual(plan({ headCommit: old }), { version: "1.0.3", retry: true, changed: false });
  assert.equal(plan({ currentVersion: "1.0.4", headCommit: next,
    publications: [{ version: "1.0.4", commit: next }, { version: "1.0.3", commit: old }] }).version, "1.0.4");
});

test("publishing new source with the same or lower visible version is rejected", () => {
  assert.throws(() => assertForwardReleaseVersion({ version: "1.0.3", publishedVersion: "1.0.3", commit: next, publishedCommit: old }), /already published/u);
  assert.throws(() => assertForwardReleaseVersion({ version: "1.0.2", publishedVersion: "1.0.3", commit: next, publishedCommit: old }), /already published/u);
  assert.doesNotThrow(() => assertForwardReleaseVersion({ version: "1.0.3", publishedVersion: "1.0.3", commit: old, publishedCommit: old }));
  assert.doesNotThrow(() => assertForwardReleaseVersion({ version: "1.0.4", publishedVersion: "1.0.3", commit: next, publishedCommit: old }));
  assert.throws(() => plan({ currentVersion: "1.0.2" }), /behind/u);
  for (const version of ["1.0.3+78", "1.0", "1.00.3", "bad", "1.0.9007199254740992"]) assert.throws(() => compareVersions(version, "1.0.3"));
});

test("reads actual desktop manifest formats without treating native counters as visible versions", () => {
  assert.deepEqual(desktopPublicationFromManifest({ short_version: "1.0.3", bundle_version: "265", commit: old }, "macos"), { version: "1.0.3", commit: old });
  assert.deepEqual(desktopPublicationFromManifest({ release_name: "Vinabike ERP Windows 1.0.3+61", commit: old }, "windows"), { version: "1.0.3", commit: old });
  assert.throws(() => desktopPublicationFromManifest({ version: "1.0.3", commit: old }, "windows"));
});

test("preparation writes the next source version and bound metadata once; a retry leaves them intact", async (t) => {
  const repoDir = await mkdtemp(path.join(os.tmpdir(), "release-version-test-"));
  t.after(() => rm(repoDir, { recursive: true, force: true }));
  const git = (...args) => execFileSync("git", args, { cwd: repoDir, encoding: "utf8" }).trim();
  git("init", "-q"); git("config", "user.name", "Release test"); git("config", "user.email", "release-test@example.invalid");
  await writeFile(path.join(repoDir, "pubspec.yaml"), "name: fixture\nversion: 1.0.3+61\n");
  git("add", "-A"); git("commit", "-qm", "Published source"); const published = git("rev-parse", "HEAD");
  const options = { repoDir, write: true, readDesktopPublication: async () => ({ version: "1.0.3", commit: published }),
    readAndroidPublication: async () => ({ version_name: "1.0.3", build_number: 78, commit: published }) };
  assert.equal((await prepareReleaseVersion(options)).retry, true);
  await writeFile(path.join(repoDir, "new.txt"), "New reviewed implementation\n");
  const result = await prepareReleaseVersion(options);
  assert.equal(result.version, "1.0.4"); assert.equal(result.notes_base, published);
  const pubspec = await readFile(path.join(repoDir, "pubspec.yaml"), "utf8");
  assert.equal(pubspec, "name: fixture\nversion: 1.0.4+61\n");
  const recordPath = path.join(repoDir, "docs/releases/changes/version-1.0.4.json");
  const record = JSON.parse(await readFile(recordPath, "utf8"));
  assert.equal(record.scope, "internal"); assert.deepEqual(record.items, []);
  assert.equal(record.evidence[0].sha256, createHash("sha256").update(pubspec).digest("hex"));
  const before = await readFile(recordPath, "utf8");
  assert.equal((await prepareReleaseVersion(options)).changed, false);
  assert.equal(await readFile(recordPath, "utf8"), before);
});
