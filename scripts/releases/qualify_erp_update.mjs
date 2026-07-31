#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import {
  chmod,
  lstat,
  readFile,
  realpath,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  INTEGRITY_WORKFLOW_PATH,
  validateIntegrityRun,
} from "./verify_integrity_qualification.mjs";
import { formatWorkflowFailureSummary } from "./workflow_failure_diagnostics.mjs";

const REPOSITORY = "Ccatalan7/bikeshop-erp";
const WORKFLOW = "erp-integrity-gate.yml";
const DEFAULT_STATE_FILE = "vinabike-erp-publish-state.json";
const STATE_MAX_AGE_SECONDS = 21_600;
const MAX_STATE_BYTES = 64 * 1024;
const MAX_CANDIDATE_BASE64_CHARS = 16 * 1024;
const MAX_CANDIDATE_BYTES = 12 * 1024;
const COMMIT_PATTERN = /^[0-9a-f]{40}$/u;
const SHA256_PATTERN = /^[0-9a-f]{64}$/u;
const INTEGER_PATTERN = /^[1-9][0-9]*$/u;

class SafeQualificationError extends Error {
  constructor(message) {
    super(message);
    this.name = "SafeQualificationError";
  }
}

function fail(message) {
  throw new SafeQualificationError(message);
}

function runCommand(
  command,
  args,
  { cwd, input, allowFailure = false, maxBuffer = 8 * 1024 * 1024 } = {},
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
    fail(`${command} could not complete ERP update qualification.`);
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

function sha256Hex(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function validateReleaseNotes(releaseNotes, headSha) {
  const notes = requireObject(
    releaseNotes,
    "Prepared ERP update state is missing release-note metadata.",
  );
  if (
    !COMMIT_PATTERN.test(notes.from_commit ?? "") ||
    typeof notes.candidate_b64 !== "string" ||
    typeof notes.candidate_sha256 !== "string" ||
    notes.candidate_b64.length > MAX_CANDIDATE_BASE64_CHARS
  ) {
    fail("Prepared ERP update release-note metadata is invalid.");
  }
  if (notes.candidate_b64.length === 0) {
    if (notes.candidate_sha256.length !== 0) {
      fail("Prepared ERP update release-note binding is invalid.");
    }
    return;
  }
  if (!SHA256_PATTERN.test(notes.candidate_sha256)) {
    fail("Prepared ERP update release-note candidate is invalid.");
  }
  const candidate = Buffer.from(notes.candidate_b64, "base64");
  if (
    candidate.length < 2 ||
    candidate.length > MAX_CANDIDATE_BYTES ||
    candidate.toString("base64") !== notes.candidate_b64 ||
    sha256Hex(candidate) !== notes.candidate_sha256
  ) {
    fail("Prepared ERP update release-note candidate failed its binding.");
  }
  const envelope = requireObject(
    parseJson(
      candidate.toString("utf8"),
      "Prepared ERP update release-note candidate is not valid JSON.",
    ),
    "Prepared ERP update release-note candidate is malformed.",
  );
  if (
    envelope.schema_version !== 1 ||
    envelope.from_commit !== notes.from_commit ||
    envelope.to_commit !== headSha ||
    !SHA256_PATTERN.test(envelope.evidence_catalog_sha256 ?? "") ||
    !envelope.candidate ||
    typeof envelope.candidate !== "object" ||
    Array.isArray(envelope.candidate)
  ) {
    fail("Prepared ERP update release-note candidate targets another release.");
  }
}

async function resolveStatePath(repoDir, requestedPath, gitDir) {
  const requested =
    !requestedPath || requestedPath === "auto"
      ? path.join(gitDir, DEFAULT_STATE_FILE)
      : path.resolve(repoDir, requestedPath);
  const parent = await realpath(path.dirname(requested)).catch(() => "");
  if (!parent) fail("Could not resolve the prepared ERP update state.");
  const resolved = path.join(parent, path.basename(requested));
  const relative = path.relative(gitDir, resolved);
  if (
    relative === "" ||
    relative === ".." ||
    relative.startsWith(`..${path.sep}`) ||
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
    run("git", ["rev-parse", "--absolute-git-dir"], {
      cwd: repositoryRoot,
    }),
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
  if (stateStat.size < 2 || stateStat.size > MAX_STATE_BYTES) {
    fail("Prepared ERP update state is outside its size boundary.");
  }
  const state = requireObject(
    parseJson(
      await readFile(statePath, "utf8"),
      "Prepared ERP update state is not valid JSON.",
    ),
    "Prepared ERP update state is malformed.",
  );
  const pairedTargets =
    Array.isArray(state.targets) &&
    state.targets.includes("android") &&
    (state.targets.includes("macos") || state.targets.includes("windows"));
  if (
    (state.schema_version !== 2 && state.schema_version !== 3) ||
    !pairedTargets ||
    state.remote !== "origin" ||
    typeof state.repository_root !== "string" ||
    typeof state.branch !== "string" ||
    state.branch.length < 1 ||
    state.branch.length > 255 ||
    !COMMIT_PATTERN.test(state.head_sha ?? "") ||
    !Number.isInteger(state.created_epoch)
  ) {
    fail("Prepared ERP update state does not authorize paired qualification.");
  }
  const age = nowEpoch - state.created_epoch;
  if (age < 0 || age > STATE_MAX_AGE_SECONDS) {
    fail("Prepared ERP update state is stale; run the top-level task again.");
  }
  const stateRoot = await realpath(state.repository_root).catch(() => "");
  if (stateRoot !== repositoryRoot) {
    fail("Prepared ERP update state belongs to another repository checkout.");
  }
  validateReleaseNotes(state.release_notes, state.head_sha);
  return { state, statePath, repositoryRoot };
}

export function assertPreparedSource(prepared, { run = runCommand } = {}) {
  const { state, repositoryRoot } = prepared;
  const branch = run("git", ["branch", "--show-current"], {
    cwd: repositoryRoot,
  });
  const head = run("git", ["rev-parse", "HEAD"], { cwd: repositoryRoot });
  const status = run("git", ["status", "--porcelain"], {
    cwd: repositoryRoot,
  });
  if (branch !== state.branch || head !== state.head_sha) {
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
        state.release_notes.from_commit,
        state.head_sha,
      ],
      { cwd: repositoryRoot, allowFailure: true },
    ) === null
  ) {
    fail("The prepared release-note base is not an ancestor of the update.");
  }
  const remoteLine = run(
    "git",
    ["ls-remote", "--heads", state.remote, `refs/heads/${state.branch}`],
    { cwd: repositoryRoot },
  );
  const remoteHead = remoteLine.split(/\s+/u)[0] ?? "";
  if (remoteHead !== state.head_sha) {
    fail("The live remote branch no longer matches the prepared ERP update.");
  }
}

function parseRuns(text) {
  const parsed = parseJson(text || "[]", "GitHub returned invalid gate runs.");
  if (!Array.isArray(parsed)) fail("GitHub returned invalid gate runs.");
  return parsed;
}

function newest(runs) {
  return [...runs]
    .sort((left, right) =>
      String(left?.createdAt ?? "").localeCompare(
        String(right?.createdAt ?? ""),
      ),
    )
    .at(-1);
}

export function chooseExactQualificationRun(runs, headSha) {
  const exact = runs.filter(
    (run) =>
      run?.headSha === headSha &&
      run?.workflowName === "ERP Integrity Gate" &&
      (run?.event === "push" || run?.event === "workflow_dispatch"),
  );
  return (
    newest(
      exact.filter(
        (run) => run.status === "completed" && run.conclusion === "success",
      ),
    ) ??
    newest(exact.filter((run) => run.status !== "completed")) ??
    newest(exact.filter((run) => run.status === "completed")) ??
    null
  );
}

function listQualificationRuns(prepared, run) {
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
        prepared.state.branch,
        "--limit",
        "50",
        "--json",
        "attempt,conclusion,createdAt,databaseId,event,headSha,status,url,workflowDatabaseId,workflowName",
      ],
      { cwd: prepared.repositoryRoot },
    ),
  );
}

function defaultWait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export async function findOrDispatchQualificationRun(
  prepared,
  {
    run = runCommand,
    wait = defaultWait,
    discoveryTimeoutMs = 60_000,
    lookupTimeoutMs = 5 * 60_000,
    pollIntervalMs = 5_000,
  } = {},
) {
  const discoveryPolls = Math.max(
    1,
    Math.floor(discoveryTimeoutMs / Math.max(1, pollIntervalMs)) + 1,
  );
  let runs = [];
  for (let poll = 0; poll < discoveryPolls; poll += 1) {
    runs = listQualificationRuns(prepared, run);
    const existing = chooseExactQualificationRun(runs, prepared.state.head_sha);
    if (existing) return { workflowRun: existing, dispatched: false };
    if (poll + 1 < discoveryPolls) await wait(pollIntervalMs);
  }

  // Re-list immediately before dispatch so a just-created queued/pending run is
  // reused instead of creating a second exact-SHA qualification.
  runs = listQualificationRuns(prepared, run);
  const lastMomentRun = chooseExactQualificationRun(
    runs,
    prepared.state.head_sha,
  );
  if (lastMomentRun) {
    return { workflowRun: lastMomentRun, dispatched: false };
  }
  const remoteLine = run(
    "git",
    [
      "ls-remote",
      "--heads",
      prepared.state.remote ?? "origin",
      `refs/heads/${prepared.state.branch}`,
    ],
    { cwd: prepared.repositoryRoot },
  );
  if ((remoteLine.split(/\s+/u)[0] ?? "") !== prepared.state.head_sha) {
    fail(
      "The live branch moved before ERP qualification could be dispatched. " +
        "Run the top-level task again.",
    );
  }
  const beforeIds = new Set(runs.map((candidate) => candidate.databaseId));
  run(
    "gh",
    [
      "workflow",
      "run",
      WORKFLOW,
      "--repo",
      REPOSITORY,
      "--ref",
      prepared.state.branch,
      "--json",
    ],
    {
      cwd: prepared.repositoryRoot,
      input: `${JSON.stringify({ expected_commit: prepared.state.head_sha })}\n`,
    },
  );

  const lookupPolls = Math.max(
    1,
    Math.floor(lookupTimeoutMs / Math.max(1, pollIntervalMs)) + 1,
  );
  for (let poll = 0; poll < lookupPolls; poll += 1) {
    const candidates = listQualificationRuns(prepared, run).filter(
      (candidate) => !beforeIds.has(candidate.databaseId),
    );
    const found = chooseExactQualificationRun(
      candidates,
      prepared.state.head_sha,
    );
    if (found) return { workflowRun: found, dispatched: true };
    if (poll + 1 < lookupPolls) await wait(pollIntervalMs);
  }
  fail("GitHub accepted ERP qualification, but its exact run was not found.");
}

function getLiveRun(prepared, runId, run) {
  const text = run("gh", ["api", `repos/${REPOSITORY}/actions/runs/${runId}`], {
    cwd: prepared.repositoryRoot,
  });
  return requireObject(
    parseJson(text, "GitHub returned invalid ERP qualification status."),
    "GitHub returned invalid ERP qualification status.",
  );
}

function showFailureDiagnostics(prepared, runId, run) {
  const jobs =
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
        cwd: prepared.repositoryRoot,
        allowFailure: true,
        maxBuffer: 4 * 1024 * 1024,
      },
    ) ?? "";
  const failedLog =
    run(
      "gh",
      ["run", "view", String(runId), "--repo", REPOSITORY, "--log-failed"],
      {
        cwd: prepared.repositoryRoot,
        allowFailure: true,
        maxBuffer: 8 * 1024 * 1024,
      },
    ) ?? "";
  process.stderr.write(
    `${formatWorkflowFailureSummary(jobs, failedLog, {
      fallbackPrefix: "erp-qualification",
    })}\n`,
  );
}

export async function waitForQualification(
  prepared,
  workflowRun,
  {
    run = runCommand,
    wait = defaultWait,
    timeoutMs = 50 * 60_000,
    pollIntervalMs = 30_000,
  } = {},
) {
  const runId = String(workflowRun?.databaseId ?? "");
  if (!INTEGER_PATTERN.test(runId)) {
    fail("GitHub returned an invalid ERP qualification run.");
  }
  const polls = Math.max(
    1,
    Math.floor(timeoutMs / Math.max(1, pollIntervalMs)) + 1,
  );
  const retryableConclusions = new Set([
    "cancelled",
    "stale",
    "startup_failure",
    "timed_out",
  ]);
  let minimumAttempt = Number(workflowRun?.attempt ?? 1);
  let transientRerunUsed = false;
  for (let poll = 0; poll < polls; poll += 1) {
    const live = getLiveRun(prepared, runId, run);
    process.stdout.write(
      `ERP qualification: ${live.status ?? "unknown"} · ` +
        `attempt ${live.run_attempt ?? "?"}\n`,
    );
    if (
      transientRerunUsed &&
      Number.isInteger(live.run_attempt) &&
      live.run_attempt < minimumAttempt
    ) {
      if (poll + 1 < polls) await wait(pollIntervalMs);
      continue;
    }
    if (live.status === "completed") {
      if (live.conclusion !== "success") {
        if (
          !transientRerunUsed &&
          retryableConclusions.has(live.conclusion) &&
          live.run_attempt === 1
        ) {
          process.stdout.write(
            `ERP qualification ended as ${live.conclusion}; retrying this ` +
              "same run once.\n",
          );
          run("gh", ["run", "rerun", runId, "--repo", REPOSITORY], {
            cwd: prepared.repositoryRoot,
          });
          transientRerunUsed = true;
          minimumAttempt = 2;
          if (poll + 1 < polls) await wait(pollIntervalMs);
          continue;
        }
        showFailureDiagnostics(prepared, runId, run);
        fail(
          `ERP Integrity Gate already ${live.conclusion ?? "failed"} for ` +
            `${prepared.state.head_sha}. Fix that exact failure before publishing.`,
        );
      }
      validateIntegrityRun(live, {
        repository: REPOSITORY,
        headSha: prepared.state.head_sha,
        branch: prepared.state.branch,
        runId,
        runAttempt: String(live.run_attempt ?? ""),
      });
      return live;
    }
    if (poll + 1 < polls) await wait(pollIntervalMs);
  }
  fail("ERP integrity qualification exceeded its bounded wait time.");
}

export async function writeQualification(prepared, liveRun) {
  const proof = {
    repository: REPOSITORY,
    workflow_path: INTEGRITY_WORKFLOW_PATH,
    workflow_id: liveRun.workflow_id,
    run_id: liveRun.id,
    run_attempt: liveRun.run_attempt,
    head_sha: liveRun.head_sha,
    branch: liveRun.head_branch,
    completed_at: liveRun.updated_at,
  };
  const nextState = {
    ...prepared.state,
    schema_version: 3,
    qualification: proof,
  };
  const stateDirectory = path.dirname(prepared.statePath);
  const temporaryPath = path.join(
    stateDirectory,
    `.${path.basename(prepared.statePath)}.${randomUUID()}.tmp`,
  );
  try {
    await writeFile(temporaryPath, `${JSON.stringify(nextState)}\n`, {
      encoding: "utf8",
      mode: 0o600,
      flag: "wx",
    });
    await chmod(temporaryPath, 0o600);
    if (process.platform === "win32") {
      const protectScript = [
        "& {",
        "param([string]$StatePath)",
        "$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()",
        "$security = New-Object System.Security.AccessControl.FileSecurity",
        "$security.SetOwner($identity.User)",
        "$security.SetAccessRuleProtection($true, $false)",
        "$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(",
        "$identity.User,",
        "[System.Security.AccessControl.FileSystemRights]::FullControl,",
        "[System.Security.AccessControl.AccessControlType]::Allow",
        ")",
        "$security.AddAccessRule($rule)",
        "[System.IO.File]::SetAccessControl($StatePath, $security)",
        "}",
      ].join("\n");
      runCommand(
        "powershell.exe",
        [
          "-NoLogo",
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          protectScript,
          temporaryPath,
        ],
        { cwd: prepared.repositoryRoot ?? path.dirname(prepared.statePath) },
      );
    }
    await rename(temporaryPath, prepared.statePath);
  } finally {
    await rm(temporaryPath, { force: true }).catch(() => {});
  }
  return proof;
}

function parseArguments(argv) {
  let preparedState = "auto";
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") return { help: true };
    if (argument !== "--prepared-state") {
      fail("Usage: qualify_erp_update.mjs --prepared-state <path|auto>");
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
        "Usage: node scripts/releases/qualify_erp_update.mjs " +
          "--prepared-state <path|auto>\n",
      );
      return 0;
    }
    const prepared = await loadPreparedState({
      requestedPath: args.preparedState,
    });
    assertPreparedSource(prepared);
    stdout.write(
      `Waiting for one ERP Integrity Gate at ${prepared.state.head_sha}.\n`,
    );
    const selection = await findOrDispatchQualificationRun(prepared);
    stdout.write(
      `${selection.dispatched ? "Dispatched" : "Reusing"} qualification run: ` +
        `${selection.workflowRun.url ?? "GitHub Actions"}\n`,
    );
    const liveRun = await waitForQualification(prepared, selection.workflowRun);
    const proof = await writeQualification(prepared, liveRun);
    stdout.write(
      `ERP update qualified once by run ${proof.run_id}, ` +
        `attempt ${proof.run_attempt}. Platform publishers can now start.\n`,
    );
    return 0;
  } catch (error) {
    const message =
      error instanceof SafeQualificationError ||
      error?.name === "IntegrityQualificationError"
        ? error.message
        : "ERP update qualification failed safely.";
    stderr.write(`${message}\n`);
    return 1;
  }
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === currentFile) {
  process.exitCode = await main();
}
