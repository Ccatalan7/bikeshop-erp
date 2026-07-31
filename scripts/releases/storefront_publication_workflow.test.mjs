import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  approvedFirebaseOrigin,
  approvedStoreOrigin,
  approvedSupabaseOrigin,
  approvedTenantId,
  beginPublication,
  completePublicationSuccess,
  finalizePublicationFailure,
  sealPublication,
  validateReleaseBytes,
  verifyPublishedRelease,
} from "./storefront_publication_workflow.mjs";

const requestId = "11111111-1111-4111-8111-aaaaaaaaaaaa";
const attemptId = "22222222-2222-4222-8222-222222222222";
const commit = "a".repeat(40);
const ownerSourceSha256 = "b".repeat(64);
const buildInputSha256 = "c".repeat(64);
const manifestSha256 = "d".repeat(64);
const githubRunId = "123456789";
const githubRunAttempt = "2";
const requestedRevision = "37";

function baseEnvironment(overrides = {}) {
  return {
    SUPABASE_URL: approvedSupabaseOrigin,
    SUPABASE_SECRET_KEY: "test-secret-key",
    PUBLICATION_REQUEST_ID: requestId,
    PUBLICATION_ATTEMPT_ID: attemptId,
    PUBLICATION_LEASE_FENCE: "91",
    PUBLICATION_REQUESTED_REVISION: requestedRevision,
    GITHUB_RUN_ID: githubRunId,
    GITHUB_RUN_ATTEMPT: githubRunAttempt,
    GITHUB_SHA: commit,
    GITHUB_REF: "refs/heads/main",
    ...overrides,
  };
}

function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function outputCollector() {
  const values = {};
  return {
    values,
    write(outputs) {
      Object.assign(values, outputs);
    },
  };
}

async function temporaryDirectory(t) {
  const directory = await mkdtemp(
    path.join(os.tmpdir(), "vinabike-publication-workflow-test-"),
  );
  t.after(async () => {
    await rm(directory, { recursive: true, force: true });
  });
  return directory;
}

function publicationRelease(overrides = {}) {
  return {
    commit,
    run: githubRunId,
    built_at: "2026-07-28T19:00:00Z",
    target: "store",
    source: "github-actions",
    dirty: false,
    publication: {
      request_id: requestId,
      owner_revision: Number(requestedRevision),
      owner_source_sha256: ownerSourceSha256,
      build_input_sha256: buildInputSha256,
    },
    ...overrides,
  };
}

test("begin binds only the server-owned publication envelope", async () => {
  const calls = [];
  const outputs = outputCollector();
  const result = await beginPublication({
    environment: baseEnvironment(),
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse({
        should_run: true,
        replay: false,
        reason: "bound",
        request_id: requestId,
        attempt_id: attemptId,
        lease_fence: 91,
        requested_revision: Number(requestedRevision),
        tenant_id: approvedTenantId,
        expected_store_origin: approvedStoreOrigin,
        expected_firebase_origin: approvedFirebaseOrigin,
      });
    },
    writeOutputs: outputs.write,
  });

  assert.equal(result.shouldRun, true);
  assert.equal(calls.length, 1);
  assert.equal(
    calls[0].url,
    `${approvedSupabaseOrigin}/rest/v1/rpc/` +
      "begin_storefront_publication_workflow",
  );
  assert.equal(calls[0].options.headers.apikey, "test-secret-key");
  assert.equal("authorization" in calls[0].options.headers, false);
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    p_request_id: requestId,
    p_github_run_id: Number(githubRunId),
    p_github_run_attempt: Number(githubRunAttempt),
    p_github_sha: commit,
    p_github_ref: "refs/heads/main",
  });
  assert.deepEqual(outputs.values, {
    is_publication: "true",
    should_run: "true",
    request_id: requestId,
    attempt_id: attemptId,
    lease_fence: 91,
    requested_revision: Number(requestedRevision),
    expected_firebase_origin: approvedFirebaseOrigin,
    expected_store_origin: approvedStoreOrigin,
  });
});

test("begin refuses a non-canonical request before contacting Supabase", async () => {
  for (const invalidRequestId of [
    requestId.toUpperCase(),
    ` ${requestId}`,
    `${requestId} `,
  ]) {
    let contacted = false;
    await assert.rejects(
      beginPublication({
        environment: baseEnvironment({
          PUBLICATION_REQUEST_ID: invalidRequestId,
        }),
        fetchImpl: async () => {
          contacted = true;
          return jsonResponse({});
        },
      }),
      /must be canonical lowercase/,
    );
    assert.equal(contacted, false);
  }
});

test("begin fails closed on a malformed server decision", async () => {
  await assert.rejects(
    beginPublication({
      environment: baseEnvironment(),
      fetchImpl: async () => jsonResponse({}),
      writeOutputs: () => {
        assert.fail("A malformed begin response must not emit outputs");
      },
    }),
    /Invalid begin decision/,
  );
});

test("seal binds the final owner and build hashes before deployment", async (t) => {
  const directory = await temporaryDirectory(t);
  const evidenceFile = path.join(directory, "evidence.json");
  writeFileSync(
    evidenceFile,
    JSON.stringify({
      owner_source_sha256: ownerSourceSha256,
      build_input_sha256: buildInputSha256,
    }),
  );
  const calls = [];
  const outputs = outputCollector();

  const result = await sealPublication({
    environment: baseEnvironment({
      PUBLICATION_EVIDENCE_FILE: evidenceFile,
    }),
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse({
        deploy: true,
        replay: false,
        request_id: requestId,
        attempt_id: attemptId,
        requested_revision: Number(requestedRevision),
      });
    },
    writeOutputs: outputs.write,
  });

  assert.equal(result.deploy, true);
  assert.match(
    calls[0].url,
    /\/rest\/v1\/rpc\/seal_storefront_publication_workflow$/,
  );
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    p_request_id: requestId,
    p_attempt_id: attemptId,
    p_lease_fence: 91,
    p_github_run_id: Number(githubRunId),
    p_owner_source_sha256: ownerSourceSha256,
    p_build_input_sha256: buildInputSha256,
  });
  assert.deepEqual(outputs.values, {
    deploy: "true",
    terminal: "false",
    owner_source_sha256: ownerSourceSha256,
    build_input_sha256: buildInputSha256,
  });
});

test("a changed owner revision becomes terminal without deployment", async (t) => {
  const directory = await temporaryDirectory(t);
  const evidenceFile = path.join(directory, "evidence.json");
  writeFileSync(
    evidenceFile,
    JSON.stringify({
      owner_source_sha256: ownerSourceSha256,
      build_input_sha256: buildInputSha256,
    }),
  );
  const outputs = outputCollector();

  const result = await sealPublication({
    environment: baseEnvironment({
      PUBLICATION_EVIDENCE_FILE: evidenceFile,
    }),
    fetchImpl: async () =>
      jsonResponse({
        deploy: false,
        replay: false,
        reason: "owner_revision_changed",
        requested_revision: Number(requestedRevision),
        desired_revision: Number(requestedRevision) + 1,
      }),
    writeOutputs: outputs.write,
  });

  assert.equal(result.deploy, false);
  assert.equal(result.terminal, true);
  assert.equal(outputs.values.deploy, "false");
  assert.equal(outputs.values.terminal, "true");
});

test("release evidence requires publication:null for code pushes", () => {
  const release = publicationRelease({ publication: null });
  const bytes = Buffer.from(`${JSON.stringify(release)}\n`);
  const evidence = validateReleaseBytes(bytes, {
    isPublication: false,
    commit,
    runId: githubRunId,
  });

  assert.equal(
    evidence.manifestSha256,
    createHash("sha256").update(bytes).digest("hex"),
  );
  assert.throws(
    () =>
      validateReleaseBytes(Buffer.from(JSON.stringify(publicationRelease())), {
        isPublication: false,
        commit,
        runId: githubRunId,
      }),
    /publication:null/,
  );
});

test("publication release evidence enforces its exact v2 field types", () => {
  const malformed = publicationRelease();
  malformed.publication.owner_revision = requestedRevision;
  assert.throws(
    () =>
      validateReleaseBytes(Buffer.from(JSON.stringify(malformed)), {
        isPublication: true,
        commit,
        runId: githubRunId,
        requestId,
        requestedRevision: Number(requestedRevision),
        ownerSourceSha256,
        buildInputSha256,
      }),
    /publication types/,
  );
});

test("verification requires byte-identical evidence on both origins", async (t) => {
  const directory = await temporaryDirectory(t);
  const releaseFile = path.join(directory, "release.json");
  const bytes = Buffer.from(`${JSON.stringify(publicationRelease())}\n`);
  writeFileSync(releaseFile, bytes);
  const requestedOrigins = [];
  const outputs = outputCollector();

  const evidence = await verifyPublishedRelease({
    environment: baseEnvironment({
      IS_PUBLICATION: "true",
      RELEASE_FILE: releaseFile,
      EXPECTED_COMMIT: commit,
      EXPECTED_FIREBASE_ORIGIN: approvedFirebaseOrigin,
      EXPECTED_STORE_ORIGIN: approvedStoreOrigin,
      OWNER_SOURCE_SHA256: ownerSourceSha256,
      BUILD_INPUT_SHA256: buildInputSha256,
    }),
    fetchImpl: async (url) => {
      requestedOrigins.push(url.origin);
      return new Response(bytes, {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
    writeOutputs: outputs.write,
    attempts: 1,
    retryDelayMs: 0,
  });

  const expectedDigest = createHash("sha256").update(bytes).digest("hex");
  assert.deepEqual(requestedOrigins, [
    approvedFirebaseOrigin,
    approvedStoreOrigin,
  ]);
  assert.equal(evidence.manifestSha256, expectedDigest);
  assert.deepEqual(outputs.values, {
    release_manifest_sha256: expectedDigest,
    release_built_at: "2026-07-28T19:00:00Z",
    primary_verified: "true",
    custom_verified: "true",
  });
});

test("verification rejects semantically equal but byte-different live evidence", async (t) => {
  const directory = await temporaryDirectory(t);
  const releaseFile = path.join(directory, "release.json");
  const localBytes = Buffer.from(`${JSON.stringify(publicationRelease())}\n`);
  const liveBytes = Buffer.from(
    `${JSON.stringify(publicationRelease(), null, 2)}\n`,
  );
  writeFileSync(releaseFile, localBytes);

  await assert.rejects(
    verifyPublishedRelease({
      environment: baseEnvironment({
        IS_PUBLICATION: "true",
        RELEASE_FILE: releaseFile,
        EXPECTED_COMMIT: commit,
        EXPECTED_FIREBASE_ORIGIN: approvedFirebaseOrigin,
        EXPECTED_STORE_ORIGIN: approvedStoreOrigin,
        OWNER_SOURCE_SHA256: ownerSourceSha256,
        BUILD_INPUT_SHA256: buildInputSha256,
      }),
      fetchImpl: async () => new Response(liveBytes, { status: 200 }),
      writeOutputs: () => {},
      attempts: 1,
      retryDelayMs: 0,
    }),
    /did not converge/,
  );
});

test("success completion reports the exact verified release envelope", async () => {
  const calls = [];
  const outputs = outputCollector();
  const response = await completePublicationSuccess({
    environment: baseEnvironment({
      OWNER_SOURCE_SHA256: ownerSourceSha256,
      RELEASE_MANIFEST_SHA256: manifestSha256,
      RELEASE_BUILT_AT: "2026-07-28T19:00:00Z",
      PRIMARY_VERIFIED: "true",
      CUSTOM_VERIFIED: "true",
    }),
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse({
        ok: true,
        replay: false,
        state: "succeeded",
        request_id: requestId,
        attempt_id: attemptId,
        published_revision: Number(requestedRevision),
        desired_revision: Number(requestedRevision),
      });
    },
    writeOutputs: outputs.write,
  });

  assert.equal(response.state, "succeeded");
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    p_request_id: requestId,
    p_attempt_id: attemptId,
    p_lease_fence: 91,
    p_github_run_id: Number(githubRunId),
    p_github_run_attempt: Number(githubRunAttempt),
    p_outcome: "succeeded",
    p_failure_stage: null,
    p_error_class: null,
    p_error_message: null,
    p_release_commit: commit,
    p_release_run_id: Number(githubRunId),
    p_release_built_at: "2026-07-28T19:00:00Z",
    p_release_request_id: requestId,
    p_release_revision: Number(requestedRevision),
    p_release_owner_source_sha256: ownerSourceSha256,
    p_release_manifest_sha256: manifestSha256,
    p_primary_verified: true,
    p_custom_verified: true,
  });
  assert.deepEqual(outputs.values, { completed: "true" });
});

test("the always finalizer can only report failure, including cancellation", async () => {
  const calls = [];
  await finalizePublicationFailure({
    environment: baseEnvironment({
      INTEGRITY_RESULT: "success",
      BUILD_RESULT: "cancelled",
    }),
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse({
        ok: true,
        replay: false,
        state: "queued",
        request_id: requestId,
        attempt_id: attemptId,
      });
    },
  });

  const body = JSON.parse(calls[0].options.body);
  assert.deepEqual(body, {
    p_request_id: requestId,
    p_attempt_id: attemptId,
    p_lease_fence: 91,
    p_github_run_id: Number(githubRunId),
    p_github_run_attempt: Number(githubRunAttempt),
    p_outcome: "failed",
    p_failure_stage: "workflow",
    p_error_class: "github_runner_capacity",
    p_error_message:
      "GitHub workflow cancelled before verified publication completion",
  });
  assert.equal(JSON.stringify(body).includes("succeeded"), false);
});

test("workflow exposes only request_id and orders the durable protocol", () => {
  const workflow = readFileSync(
    new URL(
      "../../.github/workflows/firebase-hosting-store.yml",
      import.meta.url,
    ),
    "utf8",
  );
  const dispatchBlock = workflow.slice(
    workflow.indexOf("  workflow_dispatch:"),
    workflow.indexOf("\njobs:"),
  );

  assert.match(
    workflow,
    /format\('Storefront publication · \{0\}', inputs\.request_id\)/,
  );
  assert.match(workflow, /format\('Storefront push · \{0\}', github\.sha\)/);
  assert.deepEqual(
    [...dispatchBlock.matchAll(/^      ([a-z_]+):$/gm)].map(
      (match) => match[1],
    ),
    ["request_id"],
  );
  assert.doesNotMatch(
    dispatchBlock,
    /^      (target_id|revision|ref|sha|origin):$/gm,
  );

  const orderedMarkers = [
    "Bind durable publication request",
    "Sync public SEO settings before build",
    "Generate SEO snapshots, sitemap, and product redirects",
    "Seal durable publication revision",
    "Write storefront release evidence",
    "Deploy store target",
    "Verify exact release evidence on both live origins",
    "Complete durable publication",
  ];
  let previousIndex = -1;
  for (const marker of orderedMarkers) {
    const index = workflow.indexOf(marker);
    assert.ok(index > previousIndex, `${marker} must be in protocol order`);
    previousIndex = index;
  }
  assert.match(
    workflow,
    /publication_finalize:[\s\S]*?always\(\)[\s\S]*?finalize-failure/,
  );
  assert.match(
    workflow,
    /release_args=\([\s\S]*?false[\s\S]*?if \[ "\$IS_PUBLICATION" = "true" \]; then[\s\S]*?release_args\+=\(/,
  );
});
