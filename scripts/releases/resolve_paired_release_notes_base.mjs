#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { lstat, mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPOSITORY = "Ccatalan7/bikeshop-erp";
const ANDROID_ARTIFACT = "vinabike-erp-android-release-evidence";
const ANDROID_MANIFEST = "android-release-manifest.json";
// Android publication is intentionally dispatched through this registered
// entrypoint. The reusable Android workflow is not independently listable on
// every repository ref.
const ANDROID_WORKFLOW = "macos-release.yml";
const COMMIT_PATTERN = /^[0-9a-f]{40}$/u;
const INTEGER_PATTERN = /^[1-9][0-9]*$/u;
const MAX_MANIFEST_BYTES = 128 * 1024;

export class PairedReleaseBaseError extends Error {
  constructor(message) {
    super(message);
    this.name = "PairedReleaseBaseError";
  }
}

function fail(message) {
  throw new PairedReleaseBaseError(message);
}

function runCommand(
  command,
  args,
  { cwd, allowFailure = false, maxBuffer = 8 * 1024 * 1024 } = {},
) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    maxBuffer,
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.error || result.status !== 0) {
    if (allowFailure) return null;
    fail(`${command} could not resolve the paired release-note baseline.`);
  }
  return String(result.stdout ?? "").trim();
}

function parseJson(text, message) {
  try {
    return JSON.parse(text);
  } catch {
    fail(message);
  }
}

function requireObject(value, message) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(message);
  }
  return value;
}

export function selectLatestAndroidRun(runs, { headSha, branch }) {
  if (!COMMIT_PATTERN.test(headSha ?? "")) {
    fail("The paired release head commit is invalid.");
  }
  if (typeof branch !== "string" || branch.length < 1 || branch.length > 255) {
    fail("The paired release branch is invalid.");
  }
  if (!Array.isArray(runs)) {
    fail("GitHub returned malformed Android release history.");
  }

  return (
    [...runs]
      .filter(
        (run) =>
          INTEGER_PATTERN.test(String(run?.databaseId ?? "")) &&
          COMMIT_PATTERN.test(run?.headSha ?? "") &&
          run.status === "completed" &&
          run.conclusion === "success" &&
          run.event === "workflow_dispatch" &&
          String(run?.displayTitle ?? "").startsWith("Android publish · "),
      )
      .sort((left, right) =>
        String(right?.createdAt ?? "").localeCompare(
          String(left?.createdAt ?? ""),
        ),
      )[0] ?? null
  );
}

export function validateAndroidPublicationManifest(manifest, expectedCommit) {
  requireObject(
    manifest,
    "The latest successful Android publication evidence is malformed.",
  );
  const notes = requireObject(
    manifest.release_notes,
    "The latest successful Android publication has no release-note evidence.",
  );
  if (
    manifest.schema_version !== 1 ||
    manifest.package_name !== "com.vinabike.erp" ||
    manifest.commit !== expectedCommit ||
    notes.schema_version !== 1 ||
    !COMMIT_PATTERN.test(notes.from_commit ?? "") ||
    notes.to_commit !== expectedCommit
  ) {
    fail("The latest successful Android publication evidence is inconsistent.");
  }
  return manifest;
}

export function androidBaselineFromManifest(manifest, headSha) {
  return manifest.commit === headSha
    ? manifest.release_notes.from_commit
    : manifest.commit;
}

async function findFiles(directory, name) {
  const matches = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      matches.push(...(await findFiles(candidate, name)));
    } else if (entry.isFile() && entry.name === name) {
      matches.push(candidate);
    }
  }
  return matches;
}

function listAndroidRuns(repositoryRoot, branch, run) {
  const parsed = parseJson(
    run(
      "gh",
      [
        "run",
        "list",
        "--repo",
        REPOSITORY,
        "--workflow",
        ANDROID_WORKFLOW,
        "--branch",
        branch,
        "--event",
        "workflow_dispatch",
        "--limit",
        "100",
        "--json",
        "databaseId,headSha,status,conclusion,event,createdAt,displayTitle",
      ],
      { cwd: repositoryRoot },
    ) || "[]",
    "GitHub returned invalid Android release history.",
  );
  if (!Array.isArray(parsed)) {
    fail("GitHub returned malformed Android release history.");
  }
  return parsed;
}

function validateLiveAndroidRun(run, expected) {
  if (
    run.id !== Number(expected.databaseId) ||
    run.repository?.full_name !== REPOSITORY ||
    run.head_repository?.full_name !== REPOSITORY ||
    run.path !== ".github/workflows/macos-release.yml" ||
    run.head_sha !== expected.headSha ||
    run.head_branch !== expected.branch ||
    run.event !== "workflow_dispatch" ||
    run.status !== "completed" ||
    run.conclusion !== "success" ||
    !String(run.display_title ?? "").startsWith("Android publish · ")
  ) {
    fail("The latest Android release run did not pass live identity checks.");
  }
}

export async function resolveLatestPriorAndroidCommit({
  repositoryRoot,
  branch,
  headSha,
  run = runCommand,
}) {
  const candidate = selectLatestAndroidRun(
    listAndroidRuns(repositoryRoot, branch, run),
    { headSha, branch },
  );
  if (!candidate) {
    fail(
      "No prior successful Android publication evidence is available for this paired release.",
    );
  }

  const liveRun = requireObject(
    parseJson(
      run(
        "gh",
        ["api", `repos/${REPOSITORY}/actions/runs/${candidate.databaseId}`],
        { cwd: repositoryRoot },
      ),
      "GitHub returned invalid Android release-run evidence.",
    ),
    "GitHub returned malformed Android release-run evidence.",
  );
  validateLiveAndroidRun(liveRun, { ...candidate, branch });

  const privateDirectory = await mkdtemp(
    path.join(os.tmpdir(), "vinabike-android-baseline-"),
  );
  try {
    run(
      "gh",
      [
        "run",
        "download",
        String(candidate.databaseId),
        "--repo",
        REPOSITORY,
        "--name",
        ANDROID_ARTIFACT,
        "--dir",
        privateDirectory,
      ],
      { cwd: repositoryRoot },
    );
    const manifests = await findFiles(privateDirectory, ANDROID_MANIFEST);
    if (manifests.length !== 1) {
      fail("The latest Android release run has no unique manifest evidence.");
    }
    const manifestStat = await lstat(manifests[0]);
    if (
      !manifestStat.isFile() ||
      manifestStat.isSymbolicLink() ||
      manifestStat.size < 2 ||
      manifestStat.size > MAX_MANIFEST_BYTES
    ) {
      fail("The latest Android release manifest is outside its size boundary.");
    }
    const manifest = validateAndroidPublicationManifest(
      parseJson(
        await readFile(manifests[0], "utf8"),
        "The latest Android release manifest is not valid JSON.",
      ),
      candidate.headSha,
    );
    return androidBaselineFromManifest(manifest, headSha);
  } finally {
    await rm(privateDirectory, { recursive: true, force: true });
  }
}

function commandSucceeded(run, args, cwd) {
  return run("git", args, { cwd, allowFailure: true }) !== null;
}

async function ensureCommit(repositoryRoot, commit, run) {
  if (
    commandSucceeded(
      run,
      ["cat-file", "-e", `${commit}^{commit}`],
      repositoryRoot,
    )
  ) {
    return;
  }
  run("git", ["fetch", "--no-tags", "origin", commit], {
    cwd: repositoryRoot,
  });
  if (
    !commandSucceeded(
      run,
      ["cat-file", "-e", `${commit}^{commit}`],
      repositoryRoot,
    )
  ) {
    fail("A paired release baseline commit is unavailable locally.");
  }
}

export function chooseCommonReleaseNotesBase(
  { desktopCommit, androidCommit, headSha },
  { isAncestor, mergeBases },
) {
  for (const commit of [desktopCommit, androidCommit, headSha]) {
    if (!COMMIT_PATTERN.test(commit ?? "")) {
      fail("A paired release baseline commit is invalid.");
    }
  }
  if (desktopCommit === headSha || androidCommit === headSha) {
    fail("A paired release baseline must precede the release head.");
  }
  if (
    !isAncestor(desktopCommit, headSha) ||
    !isAncestor(androidCommit, headSha)
  ) {
    fail("A latest platform release is not an ancestor of the paired update.");
  }
  if (desktopCommit === androidCommit) return desktopCommit;
  if (isAncestor(desktopCommit, androidCommit)) return desktopCommit;
  if (isAncestor(androidCommit, desktopCommit)) return androidCommit;

  const bases = mergeBases(desktopCommit, androidCommit);
  if (
    !Array.isArray(bases) ||
    bases.length !== 1 ||
    !COMMIT_PATTERN.test(bases[0] ?? "") ||
    bases[0] === headSha ||
    !isAncestor(bases[0], headSha)
  ) {
    fail("The platform releases have no unique safe common notes baseline.");
  }
  return bases[0];
}

export async function resolvePairedReleaseNotesBase({
  repositoryRoot = process.cwd(),
  branch,
  headSha,
  desktopCommit,
  run = runCommand,
}) {
  const androidCommit = await resolveLatestPriorAndroidCommit({
    repositoryRoot,
    branch,
    headSha,
    run,
  });
  for (const commit of [desktopCommit, androidCommit, headSha]) {
    await ensureCommit(repositoryRoot, commit, run);
  }
  const isAncestor = (ancestor, descendant) =>
    commandSucceeded(
      run,
      ["merge-base", "--is-ancestor", ancestor, descendant],
      repositoryRoot,
    );
  const mergeBases = (left, right) => {
    const output = run("git", ["merge-base", "--all", left, right], {
      cwd: repositoryRoot,
    });
    return output.split(/\r?\n/u).filter(Boolean);
  };
  return chooseCommonReleaseNotesBase(
    { desktopCommit, androidCommit, headSha },
    { isAncestor, mergeBases },
  );
}

function parseArguments(argv) {
  const parsed = { branch: "", headSha: "", desktopCommit: "" };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") return { help: true };
    const key = {
      "--branch": "branch",
      "--head-commit": "headSha",
      "--desktop-commit": "desktopCommit",
    }[argument];
    if (!key) {
      fail(
        "Usage: resolve_paired_release_notes_base.mjs --branch <branch> " +
          "--head-commit <sha> --desktop-commit <sha>",
      );
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail(`${argument} requires a value.`);
    parsed[key] = value;
    index += 1;
  }
  return parsed;
}

export async function main({
  argv = process.argv.slice(2),
  stdout = process.stdout,
  stderr = process.stderr,
} = {}) {
  try {
    const args = parseArguments(argv);
    if (args.help) {
      stdout.write(
        "Usage: node scripts/releases/resolve_paired_release_notes_base.mjs " +
          "--branch <branch> --head-commit <sha> --desktop-commit <sha>\n",
      );
      return 0;
    }
    if (
      typeof args.branch !== "string" ||
      args.branch.length < 1 ||
      args.branch.length > 255 ||
      !COMMIT_PATTERN.test(args.headSha ?? "") ||
      !COMMIT_PATTERN.test(args.desktopCommit ?? "")
    ) {
      fail("The paired release baseline request is invalid.");
    }
    const repositoryRoot = runCommand("git", ["rev-parse", "--show-toplevel"]);
    const base = await resolvePairedReleaseNotesBase({
      repositoryRoot,
      branch: args.branch,
      headSha: args.headSha,
      desktopCommit: args.desktopCommit,
    });
    stdout.write(`${base}\n`);
    return 0;
  } catch (error) {
    const message =
      error instanceof PairedReleaseBaseError
        ? error.message
        : "The paired release-note baseline could not be resolved safely.";
    stderr.write(`${message}\n`);
    return 1;
  }
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === currentFile) {
  process.exitCode = await main();
}
