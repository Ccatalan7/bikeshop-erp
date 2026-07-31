#!/usr/bin/env node

import path from "node:path";
import { fileURLToPath } from "node:url";

export const INTEGRITY_WORKFLOW_PATH =
  ".github/workflows/erp-integrity-gate.yml";

const COMMIT_PATTERN = /^[0-9a-f]{40}$/u;
const REPOSITORY_PATTERN = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u;
const INTEGER_PATTERN = /^[1-9][0-9]*$/u;
const MAX_RESPONSE_BYTES = 256 * 1024;

export class IntegrityQualificationError extends Error {
  constructor(message) {
    super(message);
    this.name = "IntegrityQualificationError";
  }
}

function fail(message) {
  throw new IntegrityQualificationError(message);
}

function requirePositiveInteger(value, label) {
  const text = String(value ?? "");
  if (!INTEGER_PATTERN.test(text)) {
    fail(`${label} is invalid.`);
  }
  const parsed = Number(text);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    fail(`${label} is invalid.`);
  }
  return parsed;
}

export function validateIntegrityRun(
  run,
  {
    repository,
    headSha,
    branch,
    runId,
    runAttempt,
    workflowPath = INTEGRITY_WORKFLOW_PATH,
  },
) {
  if (!run || typeof run !== "object" || Array.isArray(run)) {
    fail("GitHub returned malformed ERP integrity qualification evidence.");
  }
  const expectedRunId = requirePositiveInteger(runId, "Integrity run ID");
  const expectedAttempt = requirePositiveInteger(
    runAttempt,
    "Integrity run attempt",
  );
  if (!REPOSITORY_PATTERN.test(repository ?? "")) {
    fail("Expected repository identity is invalid.");
  }
  if (!COMMIT_PATTERN.test(headSha ?? "")) {
    fail("Expected integrity commit is invalid.");
  }
  if (typeof branch !== "string" || branch.length < 1 || branch.length > 255) {
    fail("Expected integrity branch is invalid.");
  }

  const eventAllowed =
    run.event === "push" || run.event === "workflow_dispatch";
  if (
    run.id !== expectedRunId ||
    run.run_attempt !== expectedAttempt ||
    run.repository?.full_name !== repository ||
    run.head_repository?.full_name !== repository ||
    run.path !== workflowPath ||
    run.name !== "ERP Integrity Gate" ||
    run.head_sha !== headSha ||
    run.head_branch !== branch ||
    run.status !== "completed" ||
    run.conclusion !== "success" ||
    !eventAllowed
  ) {
    fail(
      "The supplied ERP integrity qualification does not prove a successful " +
        "exact-source gate.",
    );
  }
  return run;
}

export async function fetchAndValidateIntegrityRun({
  runId,
  runAttempt,
  repository,
  headSha,
  branch,
  token,
  apiUrl = "https://api.github.com",
  request = globalThis.fetch,
}) {
  const numericRunId = requirePositiveInteger(runId, "Integrity run ID");
  if (typeof request !== "function") {
    fail("A GitHub API client is unavailable.");
  }
  if (typeof token !== "string" || token.length < 1) {
    fail("GITHUB_TOKEN is required to verify ERP integrity qualification.");
  }
  if (!REPOSITORY_PATTERN.test(repository ?? "")) {
    fail("Expected repository identity is invalid.");
  }
  const normalizedApiUrl = String(apiUrl).replace(/\/+$/u, "");
  if (
    !/^https:\/\/[A-Za-z0-9.-]+(?::[0-9]+)?(?:\/.*)?$/u.test(normalizedApiUrl)
  ) {
    fail("GitHub API URL is invalid.");
  }

  const response = await request(
    `${normalizedApiUrl}/repos/${repository}/actions/runs/${numericRunId}`,
    {
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
      },
    },
  ).catch(() => null);
  if (!response?.ok) {
    fail("GitHub could not verify the ERP integrity qualification run.");
  }
  const responseText = await response.text();
  if (Buffer.byteLength(responseText, "utf8") > MAX_RESPONSE_BYTES) {
    fail("GitHub returned oversized ERP integrity qualification evidence.");
  }
  let run;
  try {
    run = JSON.parse(responseText);
  } catch {
    fail("GitHub returned invalid ERP integrity qualification evidence.");
  }
  return validateIntegrityRun(run, {
    repository,
    headSha,
    branch,
    runId: numericRunId,
    runAttempt,
  });
}

function parseArguments(argv) {
  let runId = "";
  let runAttempt = "";
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") return { help: true };
    if (argument !== "--run-id" && argument !== "--run-attempt") {
      fail(
        "Usage: verify_integrity_qualification.mjs --run-id <id> " +
          "--run-attempt <attempt>",
      );
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      fail(`${argument} requires a value.`);
    }
    if (argument === "--run-id") runId = value;
    if (argument === "--run-attempt") runAttempt = value;
    index += 1;
  }
  return { runId, runAttempt };
}

export async function main({
  argv = process.argv.slice(2),
  env = process.env,
  stdout = process.stdout,
  stderr = process.stderr,
} = {}) {
  try {
    const args = parseArguments(argv);
    if (args.help) {
      stdout.write(
        "Usage: node scripts/releases/verify_integrity_qualification.mjs " +
          "--run-id <id> --run-attempt <attempt>\n",
      );
      return 0;
    }
    const run = await fetchAndValidateIntegrityRun({
      runId: args.runId,
      runAttempt: args.runAttempt,
      repository: env.GITHUB_REPOSITORY,
      headSha: env.GITHUB_SHA,
      branch: env.GITHUB_REF_NAME,
      token: env.GITHUB_TOKEN,
      apiUrl: env.GITHUB_API_URL,
    });
    stdout.write(
      `Verified ERP Integrity Gate run ${run.id}, attempt ${run.run_attempt}, ` +
        `for ${run.head_sha}.\n`,
    );
    return 0;
  } catch (error) {
    const message =
      error instanceof IntegrityQualificationError
        ? error.message
        : "ERP integrity qualification verification failed safely.";
    stderr.write(`${message}\n`);
    return 1;
  }
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === currentFile) {
  process.exitCode = await main();
}
