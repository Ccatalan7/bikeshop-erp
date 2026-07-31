#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  lstat,
  mkdtemp,
  readFile,
  readdir,
  realpath,
  rm,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { formatWorkflowFailureSummary } from "./workflow_failure_diagnostics.mjs";

export { formatWorkflowFailureSummary } from "./workflow_failure_diagnostics.mjs";

const REPOSITORY = "Ccatalan7/bikeshop-erp";
const WORKFLOW = "macos-release.yml";
const ARTIFACT_NAME = "vinabike-erp-android-release-evidence";
const MANIFEST_NAME = "android-release-manifest.json";
const PACKAGE_NAME = "com.vinabike.erp";
const STATE_FILE_NAME = "vinabike-erp-publish-state.json";
const STATE_MAX_AGE_SECONDS = 21_600;
const MAX_CANDIDATE_BASE64_CHARS = 16 * 1024;
const MAX_CANDIDATE_BYTES = 12 * 1024;
const MAX_MANIFEST_BYTES = 128 * 1024;
const MAX_APK_BYTES = 250 * 1024 * 1024;
const MAX_PART_BYTES = 40 * 1024 * 1024;
const MAX_PARTS = 8;
const MAX_ANDROID_VERSION_CODE = 2_100_000_000;
const ANDROID_ARM64_VERSION_CODE_OFFSET = 2_000;
const COMMIT_PATTERN = /^[0-9a-f]{40}$/u;
const SHA256_PATTERN = /^[0-9a-f]{64}$/u;
const BASE64_PATTERN =
  /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u;
const INTEGRITY_WORKFLOW_PATH = ".github/workflows/erp-integrity-gate.yml";

class SafeReleaseError extends Error {
  constructor(message) {
    super(message);
    this.name = "SafeReleaseError";
  }
}

function fail(message) {
  throw new SafeReleaseError(message);
}

function runCommand(
  command,
  args,
  { cwd, input, allowFailure = false, maxBuffer = 4 * 1024 * 1024 } = {},
) {
  const result = spawnSync(command, args, {
    cwd,
    input,
    encoding: "utf8",
    maxBuffer,
    stdio: ["pipe", "pipe", "pipe"],
  });
  if (result.error || result.status !== 0) {
    if (allowFailure) return null;
    fail(`${command} could not complete the protected Android release step.`);
  }
  return String(result.stdout ?? "").trim();
}

function requirePlainObject(value, message) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(message);
  }
  return value;
}

function parseJson(text, message) {
  try {
    return JSON.parse(text);
  } catch {
    fail(message);
  }
}

function sha256Hex(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function decodeCandidate(releaseNotes, headSha) {
  requirePlainObject(
    releaseNotes,
    "Prepared ERP update state is missing release-note metadata.",
  );
  const fromCommit = releaseNotes.from_commit;
  const candidateBase64 = releaseNotes.candidate_b64;
  const candidateSha256 = releaseNotes.candidate_sha256;
  if (
    !COMMIT_PATTERN.test(fromCommit) ||
    typeof candidateBase64 !== "string" ||
    typeof candidateSha256 !== "string" ||
    candidateBase64.length > MAX_CANDIDATE_BASE64_CHARS
  ) {
    fail("Prepared ERP update release-note metadata is invalid.");
  }
  if (candidateBase64.length === 0) {
    if (candidateSha256.length !== 0) {
      fail("Prepared ERP update release-note binding is invalid.");
    }
    return { fromCommit, candidateBase64, candidateSha256 };
  }
  if (
    !BASE64_PATTERN.test(candidateBase64) ||
    !SHA256_PATTERN.test(candidateSha256)
  ) {
    fail("Prepared ERP update release-note candidate is invalid.");
  }

  const decoded = Buffer.from(candidateBase64, "base64");
  if (
    decoded.length < 2 ||
    decoded.length > MAX_CANDIDATE_BYTES ||
    decoded.toString("base64") !== candidateBase64 ||
    sha256Hex(decoded) !== candidateSha256
  ) {
    fail("Prepared ERP update release-note candidate failed its binding.");
  }
  const envelope = requirePlainObject(
    parseJson(
      decoded.toString("utf8"),
      "Prepared ERP update release-note candidate is not valid JSON.",
    ),
    "Prepared ERP update release-note candidate is malformed.",
  );
  if (
    envelope.schema_version !== 1 ||
    envelope.from_commit !== fromCommit ||
    envelope.to_commit !== headSha ||
    !SHA256_PATTERN.test(envelope.evidence_catalog_sha256) ||
    !envelope.candidate ||
    typeof envelope.candidate !== "object" ||
    Array.isArray(envelope.candidate)
  ) {
    fail("Prepared ERP update release-note candidate targets another release.");
  }
  return { fromCommit, candidateBase64, candidateSha256 };
}

async function resolveStatePath(repoDir, requestedPath, gitDir) {
  const requested =
    !requestedPath || requestedPath === "auto"
      ? path.join(gitDir, STATE_FILE_NAME)
      : path.resolve(repoDir, requestedPath);
  const parent = await realpath(path.dirname(requested)).catch(() => "");
  if (!parent) fail("Could not resolve the prepared ERP update state.");
  const resolved = path.join(parent, path.basename(requested));
  const relative = path.relative(gitDir, resolved);
  if (
    relative === "" ||
    relative.startsWith(`..${path.sep}`) ||
    relative === ".." ||
    path.isAbsolute(relative)
  ) {
    fail(
      "The ERP update state file must stay inside the current Git directory.",
    );
  }
  return resolved;
}

export async function loadPreparedState({
  repoDir = process.cwd(),
  requestedPath = "auto",
  nowEpoch = Math.floor(Date.now() / 1000),
  run = runCommand,
} = {}) {
  const repositoryRoot = await realpath(
    run("git", ["rev-parse", "--show-toplevel"], { cwd: repoDir }),
  );
  const gitDir = await realpath(
    run("git", ["rev-parse", "--absolute-git-dir"], { cwd: repositoryRoot }),
  );
  const statePath = await resolveStatePath(
    repositoryRoot,
    requestedPath,
    gitDir,
  );
  const stateStat = await lstat(statePath).catch(() => null);
  if (!stateStat?.isFile() || stateStat.isSymbolicLink()) {
    fail(`Prepared ERP update state is unavailable: ${statePath}`);
  }
  if (stateStat.size < 2 || stateStat.size > 64 * 1024) {
    fail("Prepared ERP update state is outside its size boundary.");
  }

  const state = requirePlainObject(
    parseJson(
      await readFile(statePath, "utf8"),
      "Prepared ERP update state is not valid JSON.",
    ),
    "Prepared ERP update state is malformed.",
  );
  if (
    state.schema_version !== 3 ||
    !Array.isArray(state.targets) ||
    !state.targets.includes("android") ||
    state.remote !== "origin" ||
    typeof state.repository_root !== "string" ||
    typeof state.branch !== "string" ||
    state.branch.length < 1 ||
    !COMMIT_PATTERN.test(state.head_sha) ||
    !Number.isInteger(state.created_epoch)
  ) {
    fail("Prepared ERP update state does not authorize Android.");
  }
  const stateAge = nowEpoch - state.created_epoch;
  if (stateAge < 0 || stateAge > STATE_MAX_AGE_SECONDS) {
    fail("Prepared ERP update state is stale; run the top-level task again.");
  }

  const stateRoot = await realpath(state.repository_root).catch(() => "");
  if (stateRoot !== repositoryRoot) {
    fail("Prepared ERP update state belongs to another repository checkout.");
  }
  const notes = decodeCandidate(state.release_notes, state.head_sha);
  const qualification = requirePlainObject(
    state.qualification,
    "Prepared ERP update state is missing integrity qualification.",
  );
  if (
    qualification.repository !== REPOSITORY ||
    qualification.workflow_path !== INTEGRITY_WORKFLOW_PATH ||
    !Number.isSafeInteger(qualification.workflow_id) ||
    qualification.workflow_id < 1 ||
    !Number.isSafeInteger(qualification.run_id) ||
    qualification.run_id < 1 ||
    !Number.isSafeInteger(qualification.run_attempt) ||
    qualification.run_attempt < 1 ||
    qualification.head_sha !== state.head_sha ||
    qualification.branch !== state.branch ||
    typeof qualification.completed_at !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T[0-9:.]+Z$/u.test(qualification.completed_at)
  ) {
    fail("Prepared ERP update integrity qualification is malformed or stale.");
  }
  return {
    statePath,
    repositoryRoot,
    remote: state.remote,
    branch: state.branch,
    headSha: state.head_sha,
    releaseNotesFromCommit: notes.fromCommit,
    releaseNotesCandidateBase64: notes.candidateBase64,
    releaseNotesCandidateSha256: notes.candidateSha256,
    integrityWorkflowId: String(qualification.workflow_id),
    integrityRunId: String(qualification.run_id),
    integrityRunAttempt: String(qualification.run_attempt),
  };
}

export function assertPreparedSource(state, { run = runCommand } = {}) {
  const cwd = state.repositoryRoot;
  const branch = run("git", ["branch", "--show-current"], { cwd });
  const head = run("git", ["rev-parse", "HEAD"], { cwd });
  const status = run("git", ["status", "--porcelain"], { cwd });
  if (branch !== state.branch || head !== state.headSha) {
    fail("The current source no longer matches the prepared ERP update.");
  }
  if (status.length > 0) {
    fail("The worktree changed after the shared ERP update was prepared.");
  }
  if (
    run(
      "git",
      [
        "merge-base",
        "--is-ancestor",
        state.releaseNotesFromCommit,
        state.headSha,
      ],
      { cwd, allowFailure: true },
    ) === null
  ) {
    fail("The prepared release-note base is not an ancestor of the update.");
  }
  const remoteLine = run(
    "git",
    ["ls-remote", "--heads", state.remote, `refs/heads/${state.branch}`],
    { cwd },
  );
  const remoteHead = remoteLine.split(/\s+/u)[0] ?? "";
  if (remoteHead !== state.headSha) {
    fail("The live remote branch no longer matches the prepared ERP update.");
  }
}

function parseRuns(text) {
  const parsed = parseJson(
    text || "[]",
    "GitHub returned invalid workflow data.",
  );
  if (!Array.isArray(parsed)) {
    fail("GitHub returned invalid workflow data.");
  }
  return parsed;
}

function expectedAndroidRunTitle(state) {
  return [
    "Android publish",
    state.headSha,
    `notes ${state.releaseNotesCandidateSha256 || "fallback"}`,
    `from ${state.releaseNotesFromCommit || "auto"}`,
    `integrity ${state.integrityRunId || "self"}`,
  ].join(" · ");
}

function isAndroidRun(run, state) {
  return (
    run?.headSha === state.headSha &&
    run?.displayTitle === expectedAndroidRunTitle(state)
  );
}

function newestRun(runs) {
  return [...runs]
    .sort((left, right) =>
      String(left?.createdAt ?? "").localeCompare(
        String(right?.createdAt ?? ""),
      ),
    )
    .at(-1);
}

function listRuns(state, run) {
  return parseRuns(
    run(
      "gh",
      [
        "run",
        "list",
        "--repo",
        REPOSITORY,
        "--workflow",
        WORKFLOW,
        "--branch",
        state.branch,
        "--event",
        "workflow_dispatch",
        "--limit",
        "30",
        "--json",
        "databaseId,headSha,status,conclusion,url,createdAt,displayTitle",
      ],
      { cwd: state.repositoryRoot },
    ),
  );
}

export function dispatchWorkflow(state, run) {
  const payload = {
    release_target: "android",
    publish_release: "true",
    expected_commit: state.headSha,
    release_notes_from_commit: state.releaseNotesFromCommit,
    release_notes_candidate_b64: state.releaseNotesCandidateBase64,
    release_notes_candidate_sha256: state.releaseNotesCandidateSha256,
    integrity_run_id: state.integrityRunId,
    integrity_run_attempt: state.integrityRunAttempt,
  };
  run(
    "gh",
    [
      "workflow",
      "run",
      WORKFLOW,
      "--repo",
      REPOSITORY,
      "--ref",
      state.branch,
      "--json",
    ],
    {
      cwd: state.repositoryRoot,
      input: `${JSON.stringify(payload)}\n`,
    },
  );
}

function defaultWait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export async function findOrDispatchRun(
  state,
  {
    run = runCommand,
    wait = defaultWait,
    lookupTimeoutMs = 5 * 60 * 1000,
  } = {},
) {
  const before = listRuns(state, run);
  const successful = newestRun(
    before.filter(
      (candidate) =>
        isAndroidRun(candidate, state) &&
        candidate.status === "completed" &&
        candidate.conclusion === "success",
    ),
  );
  if (successful) return successful;
  const active = newestRun(
    before.filter(
      (candidate) =>
        isAndroidRun(candidate, state) && candidate.status !== "completed",
    ),
  );
  if (active) return active;

  const beforeIds = new Set(before.map((candidate) => candidate.databaseId));
  dispatchWorkflow(state, run);
  const deadline = Date.now() + lookupTimeoutMs;
  while (Date.now() < deadline) {
    const candidate = newestRun(
      listRuns(state, run).filter(
        (workflowRun) =>
          isAndroidRun(workflowRun, state) &&
          !beforeIds.has(workflowRun.databaseId),
      ),
    );
    if (candidate) return candidate;
    await wait(10_000);
  }
  fail("GitHub accepted Android publication, but its run was not found.");
}

export async function waitForRun(
  workflowRun,
  { state, run = runCommand, wait = defaultWait } = {},
) {
  const runId = String(workflowRun.databaseId ?? "");
  if (!/^[0-9]+$/u.test(runId)) {
    fail("GitHub returned an invalid Android workflow run.");
  }
  const started = Date.now();
  while (true) {
    const view = requirePlainObject(
      parseJson(
        run(
          "gh",
          [
            "run",
            "view",
            runId,
            "--repo",
            REPOSITORY,
            "--json",
            "status,conclusion,url",
          ],
          { cwd: state.repositoryRoot },
        ),
        "GitHub returned invalid Android workflow status.",
      ),
      "GitHub returned invalid Android workflow status.",
    );
    const elapsedSeconds = Math.floor((Date.now() - started) / 1000);
    process.stdout.write(
      `Android Actions: ${view.status ?? "unknown"} · ${elapsedSeconds}s\n`,
    );
    if (view.status === "completed") {
      if (view.conclusion !== "success") {
        const jobsJson =
          run(
            "gh",
            [
              "api",
              "--method",
              "GET",
              `repos/${REPOSITORY}/actions/runs/${runId}/jobs`,
              "-f",
              "per_page=100",
            ],
            {
              cwd: state.repositoryRoot,
              allowFailure: true,
              maxBuffer: 4 * 1024 * 1024,
            },
          ) ?? "";
        const failedLog = run(
          "gh",
          ["run", "view", runId, "--repo", REPOSITORY, "--log-failed"],
          {
            cwd: state.repositoryRoot,
            allowFailure: true,
            maxBuffer: 8 * 1024 * 1024,
          },
        );
        if (failedLog) {
          process.stderr.write(
            `${failedLog
              .split(/\r?\n/u)
              .slice(-200)
              .map((line) => line.slice(0, 1000))
              .join("\n")}\n`,
          );
        }
        fail(
          `Android publication failed. Check ${view.url ?? "GitHub Actions"}.\n` +
            formatWorkflowFailureSummary(jobsJson, failedLog ?? "", {
              fallbackPrefix: "android-update",
            }),
        );
      }
      return runId;
    }
    await wait(30_000);
  }
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

export function validateAndroidManifest(
  manifest,
  expectedCommit,
  expectedFromCommit,
) {
  requirePlainObject(manifest, "Android publication evidence is malformed.");
  if (
    !COMMIT_PATTERN.test(expectedFromCommit ?? "") ||
    manifest.schema_version !== 1 ||
    manifest.package_name !== PACKAGE_NAME ||
    manifest.commit !== expectedCommit ||
    typeof manifest.version_name !== "string" ||
    manifest.version_name.length < 1 ||
    manifest.version_name.length > 64 ||
    !Number.isInteger(manifest.build_number) ||
    manifest.build_number < 1 ||
    manifest.build_number >
      MAX_ANDROID_VERSION_CODE - ANDROID_ARM64_VERSION_CODE_OFFSET ||
    !Number.isInteger(manifest.version_code) ||
    manifest.version_code < 1 ||
    manifest.version_code !==
      manifest.build_number + ANDROID_ARM64_VERSION_CODE_OFFSET ||
    manifest.version_code > MAX_ANDROID_VERSION_CODE ||
    typeof manifest.apk_object_path !== "string" ||
    !manifest.apk_object_path.endsWith(
      `+${manifest.build_number}-arm64-v8a.apk`,
    ) ||
    manifest.apk_object_path.includes("..") ||
    manifest.apk_object_path.includes("\\") ||
    !SHA256_PATTERN.test(manifest.sha256) ||
    !Number.isInteger(manifest.size_bytes) ||
    manifest.size_bytes < 1 ||
    manifest.size_bytes > MAX_APK_BYTES ||
    !Array.isArray(manifest.apk_parts) ||
    manifest.apk_parts.length < 1 ||
    manifest.apk_parts.length > MAX_PARTS
  ) {
    fail("Android publication evidence does not match the requested release.");
  }

  let totalBytes = 0;
  manifest.apk_parts.forEach((part, index) => {
    requirePlainObject(
      part,
      "Android publication evidence has invalid APK parts.",
    );
    const suffix = `.part${String(index).padStart(3, "0")}`;
    if (
      part.object_path !== `${manifest.apk_object_path}${suffix}` ||
      !SHA256_PATTERN.test(part.sha256) ||
      !Number.isInteger(part.size_bytes) ||
      part.size_bytes < 1 ||
      part.size_bytes > MAX_PART_BYTES
    ) {
      fail("Android publication evidence has invalid APK parts.");
    }
    totalBytes += part.size_bytes;
  });
  if (totalBytes !== manifest.size_bytes) {
    fail("Android publication evidence has inconsistent APK sizes.");
  }

  const notes = requirePlainObject(
    manifest.release_notes,
    "Android publication evidence is missing structured release notes.",
  );
  if (
    notes.schema_version !== 1 ||
    notes.locale !== "es-CL" ||
    notes.from_commit !== expectedFromCommit ||
    notes.to_commit !== expectedCommit ||
    typeof notes.title !== "string" ||
    typeof notes.summary !== "string" ||
    !Array.isArray(notes.modules) ||
    notes.modules.length < 1
  ) {
    fail("Android publication evidence has invalid structured release notes.");
  }
  return manifest;
}

export async function verifyRunEvidence(
  state,
  runId,
  { run = runCommand } = {},
) {
  const privateDirectory = await mkdtemp(
    path.join(os.tmpdir(), "vinabike-android-release-evidence-"),
  );
  try {
    run(
      "gh",
      [
        "run",
        "download",
        String(runId),
        "--repo",
        REPOSITORY,
        "--name",
        ARTIFACT_NAME,
        "--dir",
        privateDirectory,
      ],
      { cwd: state.repositoryRoot },
    );
    const manifests = await findFiles(privateDirectory, MANIFEST_NAME);
    if (manifests.length !== 1) {
      fail("Android workflow evidence did not contain one exact manifest.");
    }
    const manifestStat = await lstat(manifests[0]);
    if (
      !manifestStat.isFile() ||
      manifestStat.isSymbolicLink() ||
      manifestStat.size < 2 ||
      manifestStat.size > MAX_MANIFEST_BYTES
    ) {
      fail("Android workflow evidence manifest is outside its boundary.");
    }
    return validateAndroidManifest(
      parseJson(
        await readFile(manifests[0], "utf8"),
        "Android workflow evidence manifest is not valid JSON.",
      ),
      state.headSha,
      state.releaseNotesFromCommit,
    );
  } finally {
    await rm(privateDirectory, { recursive: true, force: true });
  }
}

function parseArguments(argv) {
  let preparedState = "auto";
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") return { help: true };
    if (argument !== "--prepared-state") {
      fail("Usage: publish_android_workflow.mjs --prepared-state <path|auto>");
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      fail("--prepared-state requires a value.");
    }
    preparedState = value;
    index += 1;
  }
  return { preparedState };
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
        "Usage: node scripts/releases/publish_android_workflow.mjs --prepared-state <path|auto>\n",
      );
      return 0;
    }
    const state = await loadPreparedState({
      requestedPath: args.preparedState,
    });
    assertPreparedSource(state);
    stdout.write(`Android protected source: ${state.headSha}\n`);
    const workflowRun = await findOrDispatchRun(state);
    stdout.write(`Android workflow: ${workflowRun.url ?? "GitHub Actions"}\n`);
    const runId = await waitForRun(workflowRun, { state });
    const manifest = await verifyRunEvidence(state, runId);
    stdout.write(
      `Published Android ${manifest.version_name}+${manifest.build_number} ` +
        `(APK code ${manifest.version_code}) from ${state.headSha}.\n`,
    );
    return 0;
  } catch (error) {
    const message =
      error instanceof SafeReleaseError
        ? error.message
        : "The protected Android publisher failed safely.";
    stderr.write(`${message}\n`);
    return 1;
  }
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === currentFile) {
  process.exitCode = await main();
}
