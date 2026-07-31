#!/usr/bin/env node

import { createHash } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const approvedSupabaseOrigin =
  "https://xzdvtzdqjeyqxnkqprtf.supabase.co";
export const approvedTenantId = "5443b130-cc28-45af-a420-cd500b288890";
export const approvedFirebaseOrigin = "https://vinabike-store.web.app";
export const approvedStoreOrigin = "https://vinabike.cl";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const sha256Pattern = /^[0-9a-f]{64}$/;
const commitPattern = /^[0-9a-f]{40}$/;
const utcSecondPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const allowedBeginRefusalReasons = new Set([
  "request_not_found",
  "target_disabled_or_invalid",
  "active_attempt_missing",
  "request_already_bound",
  "github_run_already_bound",
  "request_not_dispatchable",
  "owner_revision_superseded",
  "already_terminal",
]);
const allowedTerminalStates = new Set([
  "queued",
  "superseded",
  "failed",
  "dead_letter",
]);

function fail(message) {
  throw new Error(message);
}

function requiredText(environment, name, maxLength = 2048) {
  const value = String(environment[name] ?? "").trim();
  if (!value || value.length > maxLength || /[\r\n\0]/.test(value)) {
    fail(`Invalid ${name}`);
  }
  return value;
}

function canonicalUuid(value, name) {
  const normalized = String(value ?? "")
    .trim()
    .toLowerCase();
  if (!uuidPattern.test(normalized)) fail(`Invalid ${name}`);
  return normalized;
}

function canonicalSha256(value, name) {
  const normalized = String(value ?? "")
    .trim()
    .toLowerCase();
  if (!sha256Pattern.test(normalized)) fail(`Invalid ${name}`);
  return normalized;
}

function canonicalCommit(value, name) {
  const normalized = String(value ?? "")
    .trim()
    .toLowerCase();
  if (!commitPattern.test(normalized)) fail(`Invalid ${name}`);
  return normalized;
}

function positiveInteger(value, name) {
  const normalized = String(value ?? "").trim();
  if (!/^[1-9][0-9]*$/.test(normalized)) fail(`Invalid ${name}`);
  const number = Number(normalized);
  if (!Number.isSafeInteger(number) || number <= 0) fail(`Invalid ${name}`);
  return number;
}

function exactObject(value, name) {
  if (!value || Array.isArray(value) || typeof value !== "object") {
    fail(`Invalid ${name} response`);
  }
  return value;
}

function exactKeys(value, keys, name) {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (
    actual.length !== expected.length ||
    actual.some((key, index) => key !== expected[index])
  ) {
    fail(`Invalid ${name} shape`);
  }
}

function sha256Hex(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

export function writeGitHubOutputs(
  outputs,
  outputPath = process.env.GITHUB_OUTPUT,
) {
  if (!outputPath) fail("Missing GITHUB_OUTPUT");
  for (const [key, rawValue] of Object.entries(outputs)) {
    if (!/^[a-z][a-z0-9_]*$/.test(key)) fail("Invalid output key");
    const value = String(rawValue);
    if (/[\r\n\0]/.test(value)) fail(`Invalid output ${key}`);
    appendFileSync(outputPath, `${key}=${value}\n`, { encoding: "utf8" });
  }
}

export async function callPublicationRpc(
  name,
  body,
  { environment = process.env, fetchImpl = globalThis.fetch } = {},
) {
  const supabaseOrigin = requiredText(environment, "SUPABASE_URL", 200).replace(
    /\/+$/,
    "",
  );
  if (supabaseOrigin !== approvedSupabaseOrigin) {
    fail("Unexpected Supabase project");
  }
  const secret = requiredText(environment, "SUPABASE_SECRET_KEY", 1000);
  const response = await fetchImpl(
    `${supabaseOrigin}/rest/v1/rpc/${encodeURIComponent(name)}`,
    {
      method: "POST",
      headers: {
        apikey: secret,
        "content-type": "application/json",
        accept: "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(30_000),
    },
  );
  if (!response.ok) {
    fail(`RPC ${name} returned HTTP ${response.status}`);
  }
  const responseText = await response.text();
  if (responseText.length > 64 * 1024) {
    fail(`RPC ${name} returned an oversized response`);
  }
  try {
    return exactObject(JSON.parse(responseText), name);
  } catch (error) {
    if (error instanceof Error && error.message.startsWith(`Invalid ${name}`)) {
      throw error;
    }
    fail(`RPC ${name} returned invalid JSON`);
  }
}

export async function beginPublication({
  environment = process.env,
  fetchImpl = globalThis.fetch,
  writeOutputs = writeGitHubOutputs,
} = {}) {
  const suppliedRequestId = String(environment.PUBLICATION_REQUEST_ID ?? "");
  const requestId = canonicalUuid(
    requiredText(environment, "PUBLICATION_REQUEST_ID", 36),
    "PUBLICATION_REQUEST_ID",
  );
  if (suppliedRequestId !== requestId) {
    fail("PUBLICATION_REQUEST_ID must be canonical lowercase");
  }
  const githubRunId = positiveInteger(
    requiredText(environment, "GITHUB_RUN_ID", 24),
    "GITHUB_RUN_ID",
  );
  const githubRunAttempt = positiveInteger(
    requiredText(environment, "GITHUB_RUN_ATTEMPT", 12),
    "GITHUB_RUN_ATTEMPT",
  );
  const githubSha = canonicalCommit(
    requiredText(environment, "GITHUB_SHA", 40),
    "GITHUB_SHA",
  );
  const githubRef = requiredText(environment, "GITHUB_REF", 120);
  if (githubRef !== "refs/heads/main") fail("Invalid GITHUB_REF");

  const response = await callPublicationRpc(
    "begin_storefront_publication_workflow",
    {
      p_request_id: requestId,
      p_github_run_id: githubRunId,
      p_github_run_attempt: githubRunAttempt,
      p_github_sha: githubSha,
      p_github_ref: githubRef,
    },
    { environment, fetchImpl },
  );

  if (response.should_run === false) {
    const reason = String(response.reason ?? "");
    if (!allowedBeginRefusalReasons.has(reason)) {
      fail("Invalid begin refusal reason");
    }
    writeOutputs({
      is_publication: "true",
      should_run: "false",
      reason,
    });
    return { shouldRun: false, reason };
  }
  if (response.should_run !== true) {
    fail("Invalid begin decision");
  }
  exactKeys(
    response,
    [
      "should_run",
      "replay",
      "reason",
      "request_id",
      "attempt_id",
      "lease_fence",
      "requested_revision",
      "tenant_id",
      "expected_store_origin",
      "expected_firebase_origin",
    ],
    "begin success",
  );
  if (typeof response.replay !== "boolean" || response.reason !== "bound") {
    fail("Invalid begin success state");
  }

  const returnedRequestId = canonicalUuid(response.request_id, "request_id");
  if (returnedRequestId !== requestId) fail("Begin request mismatch");
  const attemptId = canonicalUuid(response.attempt_id, "attempt_id");
  const leaseFence = positiveInteger(response.lease_fence, "lease_fence");
  const requestedRevision = positiveInteger(
    response.requested_revision,
    "requested_revision",
  );
  const tenantId = canonicalUuid(response.tenant_id, "tenant_id");
  if (tenantId !== approvedTenantId) fail("Unexpected publication tenant");
  if (response.expected_firebase_origin !== approvedFirebaseOrigin) {
    fail("Unexpected Firebase origin");
  }
  if (response.expected_store_origin !== approvedStoreOrigin) {
    fail("Unexpected store origin");
  }

  writeOutputs({
    is_publication: "true",
    should_run: "true",
    request_id: returnedRequestId,
    attempt_id: attemptId,
    lease_fence: leaseFence,
    requested_revision: requestedRevision,
    expected_firebase_origin: approvedFirebaseOrigin,
    expected_store_origin: approvedStoreOrigin,
  });
  return {
    shouldRun: true,
    requestId: returnedRequestId,
    attemptId,
    leaseFence,
    requestedRevision,
  };
}

export function readPublicationEvidence(path) {
  const evidencePath = String(path ?? "").trim();
  if (!evidencePath || /[\r\n\0]/.test(evidencePath)) {
    fail("Invalid publication evidence path");
  }
  let decoded;
  try {
    decoded = JSON.parse(readFileSync(evidencePath, "utf8"));
  } catch {
    fail("Publication evidence is unreadable");
  }
  const evidence = exactObject(decoded, "publication evidence");
  exactKeys(
    evidence,
    ["owner_source_sha256", "build_input_sha256"],
    "publication evidence",
  );
  return {
    ownerSourceSha256: canonicalSha256(
      evidence.owner_source_sha256,
      "owner_source_sha256",
    ),
    buildInputSha256: canonicalSha256(
      evidence.build_input_sha256,
      "build_input_sha256",
    ),
  };
}

function workflowIdentity(environment) {
  return {
    requestId: canonicalUuid(
      requiredText(environment, "PUBLICATION_REQUEST_ID", 36),
      "PUBLICATION_REQUEST_ID",
    ),
    attemptId: canonicalUuid(
      requiredText(environment, "PUBLICATION_ATTEMPT_ID", 36),
      "PUBLICATION_ATTEMPT_ID",
    ),
    leaseFence: positiveInteger(
      requiredText(environment, "PUBLICATION_LEASE_FENCE", 24),
      "PUBLICATION_LEASE_FENCE",
    ),
    githubRunId: positiveInteger(
      requiredText(environment, "GITHUB_RUN_ID", 24),
      "GITHUB_RUN_ID",
    ),
    githubRunAttempt: positiveInteger(
      requiredText(environment, "GITHUB_RUN_ATTEMPT", 12),
      "GITHUB_RUN_ATTEMPT",
    ),
  };
}

export async function sealPublication({
  environment = process.env,
  fetchImpl = globalThis.fetch,
  writeOutputs = writeGitHubOutputs,
} = {}) {
  const identity = workflowIdentity(environment);
  const requestedRevision = positiveInteger(
    requiredText(environment, "PUBLICATION_REQUESTED_REVISION", 24),
    "PUBLICATION_REQUESTED_REVISION",
  );
  const evidence = readPublicationEvidence(
    requiredText(environment, "PUBLICATION_EVIDENCE_FILE", 4096),
  );
  const response = await callPublicationRpc(
    "seal_storefront_publication_workflow",
    {
      p_request_id: identity.requestId,
      p_attempt_id: identity.attemptId,
      p_lease_fence: identity.leaseFence,
      p_github_run_id: identity.githubRunId,
      p_owner_source_sha256: evidence.ownerSourceSha256,
      p_build_input_sha256: evidence.buildInputSha256,
    },
    { environment, fetchImpl },
  );

  if (response.deploy !== true) {
    if (
      response.deploy !== false ||
      response.replay !== false ||
      response.reason !== "owner_revision_changed" ||
      positiveInteger(
        response.requested_revision,
        "seal refusal requested_revision",
      ) !== requestedRevision ||
      positiveInteger(
        response.desired_revision,
        "seal refusal desired_revision",
      ) <= requestedRevision
    ) {
      fail("Invalid seal refusal");
    }
    writeOutputs({
      deploy: "false",
      terminal: "true",
      owner_source_sha256: evidence.ownerSourceSha256,
      build_input_sha256: evidence.buildInputSha256,
    });
    return { deploy: false, terminal: true, ...evidence };
  }
  exactKeys(
    response,
    ["deploy", "replay", "request_id", "attempt_id", "requested_revision"],
    "seal success",
  );
  if (typeof response.replay !== "boolean") {
    fail("Invalid seal replay state");
  }

  if (
    canonicalUuid(response.request_id, "seal request_id") !==
      identity.requestId ||
    canonicalUuid(response.attempt_id, "seal attempt_id") !==
      identity.attemptId ||
    positiveInteger(response.requested_revision, "seal requested_revision") !==
      requestedRevision
  ) {
    fail("Seal identity mismatch");
  }
  writeOutputs({
    deploy: "true",
    terminal: "false",
    owner_source_sha256: evidence.ownerSourceSha256,
    build_input_sha256: evidence.buildInputSha256,
  });
  return { deploy: true, terminal: false, ...evidence };
}

function expectedRelease(environment) {
  const publicationValue = requiredText(environment, "IS_PUBLICATION", 5);
  if (publicationValue !== "true" && publicationValue !== "false") {
    fail("Invalid IS_PUBLICATION");
  }
  const isPublication = publicationValue === "true";
  const expected = {
    isPublication,
    commit: canonicalCommit(
      requiredText(environment, "EXPECTED_COMMIT", 40),
      "EXPECTED_COMMIT",
    ),
    runId: String(
      positiveInteger(
        requiredText(environment, "GITHUB_RUN_ID", 24),
        "GITHUB_RUN_ID",
      ),
    ),
  };
  if (!isPublication) return expected;

  return {
    ...expected,
    requestId: canonicalUuid(
      requiredText(environment, "PUBLICATION_REQUEST_ID", 36),
      "PUBLICATION_REQUEST_ID",
    ),
    requestedRevision: positiveInteger(
      requiredText(environment, "PUBLICATION_REQUESTED_REVISION", 24),
      "PUBLICATION_REQUESTED_REVISION",
    ),
    ownerSourceSha256: canonicalSha256(
      requiredText(environment, "OWNER_SOURCE_SHA256", 64),
      "OWNER_SOURCE_SHA256",
    ),
    buildInputSha256: canonicalSha256(
      requiredText(environment, "BUILD_INPUT_SHA256", 64),
      "BUILD_INPUT_SHA256",
    ),
  };
}

export function validateReleaseBytes(bytes, expected) {
  if (!Buffer.isBuffer(bytes)) bytes = Buffer.from(bytes);
  if (bytes.length === 0 || bytes.length > 64 * 1024) {
    fail("Invalid release.json size");
  }
  let release;
  try {
    release = JSON.parse(bytes.toString("utf8"));
  } catch {
    fail("Invalid release.json JSON");
  }
  release = exactObject(release, "release.json");
  exactKeys(
    release,
    ["commit", "run", "built_at", "target", "source", "dirty", "publication"],
    "release.json",
  );
  if (
    release.commit !== expected.commit ||
    typeof release.run !== "string" ||
    String(release.run) !== expected.runId ||
    typeof release.built_at !== "string" ||
    release.target !== "store" ||
    release.source !== "github-actions" ||
    release.dirty !== false
  ) {
    fail("release.json identity mismatch");
  }
  const builtAt = release.built_at;
  const builtAtMillis = Date.parse(builtAt);
  if (
    !utcSecondPattern.test(builtAt) ||
    !Number.isFinite(builtAtMillis) ||
    builtAtMillis > Date.now() + 5 * 60 * 1000
  ) {
    fail("Invalid release.json built_at");
  }

  if (!expected.isPublication) {
    if (release.publication !== null) {
      fail("Push release must contain publication:null");
    }
  } else {
    const publication = exactObject(release.publication, "release publication");
    exactKeys(
      publication,
      [
        "request_id",
        "owner_revision",
        "owner_source_sha256",
        "build_input_sha256",
      ],
      "release publication",
    );
    if (
      typeof publication.request_id !== "string" ||
      publication.request_id !== publication.request_id.toLowerCase() ||
      !Number.isSafeInteger(publication.owner_revision) ||
      publication.owner_revision <= 0 ||
      typeof publication.owner_source_sha256 !== "string" ||
      publication.owner_source_sha256 !==
        publication.owner_source_sha256.toLowerCase() ||
      typeof publication.build_input_sha256 !== "string" ||
      publication.build_input_sha256 !==
        publication.build_input_sha256.toLowerCase()
    ) {
      fail("Invalid release.json publication types");
    }
    if (
      canonicalUuid(publication.request_id, "release request_id") !==
        expected.requestId ||
      positiveInteger(publication.owner_revision, "release owner_revision") !==
        expected.requestedRevision ||
      canonicalSha256(
        publication.owner_source_sha256,
        "release owner_source_sha256",
      ) !== expected.ownerSourceSha256 ||
      canonicalSha256(
        publication.build_input_sha256,
        "release build_input_sha256",
      ) !== expected.buildInputSha256
    ) {
      fail("release.json publication mismatch");
    }
  }

  return {
    builtAt,
    manifestSha256: sha256Hex(bytes),
  };
}

async function fetchReleaseBytes(origin, expected, attempt, fetchImpl) {
  const url = new URL("/release.json", origin);
  url.searchParams.set("commit", expected.commit);
  url.searchParams.set("run", expected.runId);
  url.searchParams.set("attempt", String(attempt));
  const response = await fetchImpl(url, {
    headers: {
      accept: "application/json",
      "cache-control": "no-cache",
    },
    redirect: "error",
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) fail(`Release origin returned HTTP ${response.status}`);
  const announcedLength = Number(response.headers.get("content-length") ?? "");
  if (Number.isFinite(announcedLength) && announcedLength > 64 * 1024) {
    fail("Release origin returned oversized evidence");
  }
  return Buffer.from(await response.arrayBuffer());
}

export async function verifyPublishedRelease({
  environment = process.env,
  fetchImpl = globalThis.fetch,
  writeOutputs = writeGitHubOutputs,
  attempts = 10,
  retryDelayMs = 3000,
} = {}) {
  const expected = expectedRelease(environment);
  const releasePath = requiredText(environment, "RELEASE_FILE", 4096);
  const localBytes = readFileSync(releasePath);
  const localEvidence = validateReleaseBytes(localBytes, expected);
  const firebaseOrigin = requiredText(
    environment,
    "EXPECTED_FIREBASE_ORIGIN",
    200,
  );
  const storeOrigin = requiredText(environment, "EXPECTED_STORE_ORIGIN", 200);
  if (
    firebaseOrigin !== approvedFirebaseOrigin ||
    storeOrigin !== approvedStoreOrigin
  ) {
    fail("Unexpected release verification origin");
  }

  for (const origin of [firebaseOrigin, storeOrigin]) {
    let verified = false;
    for (let attempt = 1; attempt <= attempts; attempt += 1) {
      try {
        const liveBytes = await fetchReleaseBytes(
          origin,
          expected,
          attempt,
          fetchImpl,
        );
        const liveEvidence = validateReleaseBytes(liveBytes, expected);
        if (
          liveEvidence.manifestSha256 === localEvidence.manifestSha256 &&
          liveBytes.equals(localBytes)
        ) {
          verified = true;
          break;
        }
      } catch {
        // CDN convergence and transient reads are expected within this bounded
        // loop. No response body or live value is logged.
      }
      if (attempt < attempts && retryDelayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
      }
    }
    if (!verified) {
      fail(`Release evidence did not converge at ${origin}`);
    }
    console.log(`Verified exact release.json bytes at ${origin}`);
  }

  writeOutputs({
    release_manifest_sha256: localEvidence.manifestSha256,
    release_built_at: localEvidence.builtAt,
    primary_verified: "true",
    custom_verified: "true",
  });
  return localEvidence;
}

export async function completePublicationSuccess({
  environment = process.env,
  fetchImpl = globalThis.fetch,
  writeOutputs = writeGitHubOutputs,
} = {}) {
  const identity = workflowIdentity(environment);
  const requestedRevision = positiveInteger(
    requiredText(environment, "PUBLICATION_REQUESTED_REVISION", 24),
    "PUBLICATION_REQUESTED_REVISION",
  );
  const ownerSourceSha256 = canonicalSha256(
    requiredText(environment, "OWNER_SOURCE_SHA256", 64),
    "OWNER_SOURCE_SHA256",
  );
  const manifestSha256 = canonicalSha256(
    requiredText(environment, "RELEASE_MANIFEST_SHA256", 64),
    "RELEASE_MANIFEST_SHA256",
  );
  const releaseCommit = canonicalCommit(
    requiredText(environment, "GITHUB_SHA", 40),
    "GITHUB_SHA",
  );
  const releaseBuiltAt = requiredText(environment, "RELEASE_BUILT_AT", 64);
  if (!Number.isFinite(Date.parse(releaseBuiltAt))) {
    fail("Invalid RELEASE_BUILT_AT");
  }
  if (
    environment.PRIMARY_VERIFIED !== "true" ||
    environment.CUSTOM_VERIFIED !== "true"
  ) {
    fail("Both release origins must be verified");
  }

  const response = await callPublicationRpc(
    "complete_storefront_publication_workflow",
    {
      p_request_id: identity.requestId,
      p_attempt_id: identity.attemptId,
      p_lease_fence: identity.leaseFence,
      p_github_run_id: identity.githubRunId,
      p_github_run_attempt: identity.githubRunAttempt,
      p_outcome: "succeeded",
      p_failure_stage: null,
      p_error_class: null,
      p_error_message: null,
      p_release_commit: releaseCommit,
      p_release_run_id: identity.githubRunId,
      p_release_built_at: releaseBuiltAt,
      p_release_request_id: identity.requestId,
      p_release_revision: requestedRevision,
      p_release_owner_source_sha256: ownerSourceSha256,
      p_release_manifest_sha256: manifestSha256,
      p_primary_verified: true,
      p_custom_verified: true,
    },
    { environment, fetchImpl },
  );
  if (
    response.ok !== true ||
    typeof response.replay !== "boolean" ||
    response.state !== "succeeded" ||
    canonicalUuid(response.request_id, "complete request_id") !==
      identity.requestId ||
    canonicalUuid(response.attempt_id, "complete attempt_id") !==
      identity.attemptId
  ) {
    fail("Invalid publication success completion");
  }
  writeOutputs({ completed: "true" });
  return response;
}

export async function finalizePublicationFailure({
  environment = process.env,
  fetchImpl = globalThis.fetch,
} = {}) {
  const identity = workflowIdentity(environment);
  const integrityResult = requiredText(environment, "INTEGRITY_RESULT", 20);
  const buildResult = requiredText(environment, "BUILD_RESULT", 20);
  const validResults = new Set(["success", "failure", "cancelled", "skipped"]);
  if (!validResults.has(integrityResult) || !validResults.has(buildResult)) {
    fail("Invalid dependency result");
  }
  const cancelled =
    integrityResult === "cancelled" || buildResult === "cancelled";
  const failureStage = integrityResult === "success" ? "workflow" : "integrity";
  const errorClass = cancelled ? "github_runner_capacity" : "workflow_failed";
  const errorMessage = cancelled
    ? "GitHub workflow cancelled before verified publication completion"
    : "GitHub workflow failed before verified publication completion";

  const response = await callPublicationRpc(
    "complete_storefront_publication_workflow",
    {
      p_request_id: identity.requestId,
      p_attempt_id: identity.attemptId,
      p_lease_fence: identity.leaseFence,
      p_github_run_id: identity.githubRunId,
      p_github_run_attempt: identity.githubRunAttempt,
      p_outcome: "failed",
      p_failure_stage: failureStage,
      p_error_class: errorClass,
      p_error_message: errorMessage,
    },
    { environment, fetchImpl },
  );
  if (
    response.ok !== true ||
    typeof response.replay !== "boolean" ||
    !allowedTerminalStates.has(String(response.state ?? "")) ||
    canonicalUuid(response.request_id, "failure request_id") !==
      identity.requestId ||
    canonicalUuid(response.attempt_id, "failure attempt_id") !==
      identity.attemptId
  ) {
    fail("Invalid publication failure completion");
  }
  return response;
}

async function main() {
  const command = process.argv[2] ?? "";
  switch (command) {
    case "begin":
      await beginPublication();
      return;
    case "seal":
      await sealPublication();
      return;
    case "verify":
      await verifyPublishedRelease();
      return;
    case "complete-success":
      await completePublicationSuccess();
      return;
    case "finalize-failure":
      await finalizePublicationFailure();
      return;
    default:
      fail(
        "Expected begin, seal, verify, complete-success, or finalize-failure",
      );
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  main().catch((error) => {
    const message =
      error instanceof Error ? error.message : "Unknown publication failure";
    console.error(`Storefront publication workflow helper failed: ${message}`);
    process.exitCode = 1;
  });
}
