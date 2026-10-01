#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveLatestAndroidPublicationManifest } from "./resolve_paired_release_notes_base.mjs";

const REPO = "Ccatalan7/bikeshop-erp";
const VERSION = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/u;
const COMMIT = /^[a-f0-9]{40}$/u;

export function compareVersions(a, b) {
  if (!VERSION.test(a ?? "") || !VERSION.test(b ?? "")) throw new Error("Release versions must be major.minor.patch.");
  const left = a.split(".").map(Number);
  const right = b.split(".").map(Number);
  if (![...left, ...right].every(Number.isSafeInteger)) throw new Error("Release version numbers are too large.");
  for (let i = 0; i < 3; i++) if (left[i] !== right[i]) return left[i] > right[i] ? 1 : -1;
  return 0;
}

export function assertForwardReleaseVersion({ version, publishedVersion, commit, publishedCommit }) {
  const comparison = compareVersions(version, publishedVersion);
  if (!COMMIT.test(commit ?? "") || !COMMIT.test(publishedCommit ?? "")) throw new Error("Release version checks require exact source commits.");
  if (comparison < 0 || (comparison === 0 && commit !== publishedCommit)) {
    throw new Error(`Version ${version} is already published. Prepare a new visible version after ${publishedVersion}.`);
  }
}

export function planReleaseVersion({ currentVersion, publications, headCommit, dirty }) {
  if (!COMMIT.test(headCommit ?? "") || !Array.isArray(publications) || !publications.length) throw new Error("Verified publication history is required.");
  const ordered = [...publications].sort((a, b) => compareVersions(b.version, a.version));
  for (const publication of ordered) {
    if (!COMMIT.test(publication.commit ?? "")) throw new Error("A publication has invalid source evidence.");
  }
  const published = ordered[0].version;
  const comparison = compareVersions(currentVersion, published);
  if (comparison < 0) throw new Error("The source version is behind the published version; recover the current source first.");
  const retry = !dirty && ordered.some((p) => p.commit === headCommit && p.version === currentVersion);
  if (comparison > 0 || retry) return { version: currentVersion, retry, changed: false };
  const [major, minor, patch] = published.split(".").map(Number);
  if (!Number.isSafeInteger(patch + 1)) throw new Error("The next patch version is outside its number boundary.");
  return { version: `${major}.${minor}.${patch + 1}`, retry: false, changed: true };
}

function command(repoDir, bin, args) {
  return execFileSync(bin, args, { cwd: repoDir, encoding: "utf8", maxBuffer: 8 * 1024 * 1024 }).trim();
}

export function desktopPublicationFromManifest(manifest, desktop) {
  const version = desktop === "macos" ? manifest.short_version :
    /^Vinabike ERP Windows ([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?$/u.exec(manifest.release_name ?? "")?.[1];
  compareVersions(version, version);
  if (!COMMIT.test(manifest.commit ?? "")) throw new Error("The desktop publication has invalid source evidence.");
  return { version, commit: manifest.commit };
}

async function desktopPublication(repoDir, desktop) {
  const manifestName = `${desktop}-release-manifest.json`;
  let tag = "macos-latest";
  if (desktop === "windows") {
    // Windows uses immutable release tags; it has no windows-latest alias.
    const pages = JSON.parse(command(repoDir, "gh", ["api", "--paginate", "--slurp", `repos/${REPO}/releases?per_page=100`]));
    const release = pages.flat().filter((r) => !r.draft && !r.prerelease && r.tag_name.startsWith("windows-v") &&
      r.assets?.some((asset) => asset.name === manifestName)).sort((a, b) => b.published_at.localeCompare(a.published_at))[0];
    if (!release) throw new Error("No verified Windows publication is available.");
    tag = release.tag_name;
  }
  const text = command(repoDir, "gh", ["release", "download", tag, "--repo", REPO, "--pattern", manifestName, "--output", "-"]);
  const manifest = JSON.parse(text);
  if (desktop === "windows" && (manifest.tag_name !== tag || manifest.publish_requested !== true)) throw new Error("The Windows manifest does not identify a published release.");
  return desktopPublicationFromManifest(manifest, desktop);
}

export async function prepareReleaseVersion({ repoDir = process.cwd(), desktop = "macos", write = false,
  readDesktopPublication = desktopPublication, readAndroidPublication = resolveLatestAndroidPublicationManifest } = {}) {
  if (!["macos", "windows"].includes(desktop)) throw new Error("Select a supported desktop release channel.");
  const head = command(repoDir, "git", ["rev-parse", "HEAD"]);
  const branch = command(repoDir, "git", ["branch", "--show-current"]);
  const desktopRelease = await readDesktopPublication(repoDir, desktop);
  const android = await readAndroidPublication({ repositoryRoot: repoDir, branch, headSha: head });
  const publications = [desktopRelease, { version: android.version_name, commit: android.commit }];
  for (const publication of publications) command(repoDir, "git", ["merge-base", "--is-ancestor", publication.commit, head]);
  const notesBase = command(repoDir, "git", ["merge-base", desktopRelease.commit, android.commit]);
  const file = path.join(repoDir, "pubspec.yaml");
  const content = await readFile(file, "utf8");
  const match = /^version:[ \t]*([^+\s]+)(\+[1-9][0-9]*)?[ \t]*$/mu.exec(content);
  if (!match) throw new Error("pubspec.yaml has no valid release version.");
  const dirty = Boolean(command(repoDir, "git", ["status", "--porcelain"]));
  const plan = planReleaseVersion({ currentVersion: match[1], publications, headCommit: head, dirty });
  if (write && plan.changed) {
    const next = content.slice(0, match.index) + `version: ${plan.version}${match[2] ?? "+1"}` + content.slice(match.index + match[0].length);
    // The automatic version change is metadata, not an invented user benefit.
    const directory = path.join(repoDir, "docs/releases/changes");
    await mkdir(directory, { recursive: true });
    const recordPath = path.join(directory, `version-${plan.version}.json`);
    try {
      await readFile(recordPath);
      throw new Error("A record already exists for the next version; review it before publication.");
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    await writeFile(recordPath, JSON.stringify({
      schema_version: 1, id: `version-${plan.version.replaceAll(".", "-")}`, source: "ai", scope: "internal",
      platforms: ["macos", "windows", "android", "web", "ios"], module: "general",
      title: "", summary: "", items: [],
      evidence: [{ path: "pubspec.yaml", sha256: createHash("sha256").update(next).digest("hex") }],
    }, null, 2) + "\n", { flag: "wx" });
    await writeFile(file, next);
  }
  return { ...plan, notes_base: notesBase, publications };
}

async function main() {
  const args = process.argv.slice(2);
  if (args[0] === "--check-desktop") {
    const [desktop, version, commit] = args.slice(1);
    if (!["macos", "windows"].includes(desktop) || args.length !== 4) throw new Error("Select an exact desktop publication to check.");
    const published = await desktopPublication(process.cwd(), desktop);
    assertForwardReleaseVersion({ version, publishedVersion: published.version, commit, publishedCommit: published.commit });
    return;
  }
  if (args[0] === "--assert-forward") {
    if (args.length !== 5) throw new Error("Select exact published and new release versions and commits.");
    const [version, publishedVersion, commit, publishedCommit] = args.slice(1);
    assertForwardReleaseVersion({ version, publishedVersion, commit, publishedCommit });
    return;
  }
  if (!args.includes("--prepare") || args.some((arg) => !["--prepare", "--write", "--macos", "--windows"].includes(arg))) throw new Error("Use --prepare [--write] [--macos|--windows] or --assert-forward version publishedVersion commit publishedCommit.");
  console.log(JSON.stringify(await prepareReleaseVersion({ desktop: args.includes("--windows") ? "windows" : "macos", write: args.includes("--write") })));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(`Release version preparation failed: ${error.message}`); process.exitCode = 1; });
}
