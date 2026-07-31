#!/usr/bin/env node

import assert from "node:assert/strict";
import test from "node:test";

import {
  fetchAndValidateIntegrityRun,
  validateIntegrityRun,
} from "./verify_integrity_qualification.mjs";

const REPOSITORY = "Ccatalan7/bikeshop-erp";
const HEAD_SHA = "a".repeat(40);
const BRANCH = "smartpegas1.0";

function successfulRun(overrides = {}) {
  return {
    id: 123456,
    run_attempt: 2,
    name: "ERP Integrity Gate",
    path: ".github/workflows/erp-integrity-gate.yml",
    event: "push",
    head_sha: HEAD_SHA,
    head_branch: BRANCH,
    status: "completed",
    conclusion: "success",
    repository: { full_name: REPOSITORY },
    head_repository: { full_name: REPOSITORY },
    ...overrides,
  };
}

const expected = {
  repository: REPOSITORY,
  headSha: HEAD_SHA,
  branch: BRANCH,
  runId: "123456",
  runAttempt: "2",
};

test("accepts one successful exact-SHA integrity run", () => {
  assert.equal(validateIntegrityRun(successfulRun(), expected).id, 123456);
});

for (const [label, overrides] of [
  ["another commit", { head_sha: "b".repeat(40) }],
  ["another branch", { head_branch: "main" }],
  ["another workflow", { path: ".github/workflows/macos-release.yml" }],
  ["another attempt", { run_attempt: 1 }],
  ["an unsuccessful run", { conclusion: "failure" }],
  ["an incomplete run", { status: "in_progress", conclusion: null }],
]) {
  test(`rejects qualification evidence from ${label}`, () => {
    assert.throws(
      () => validateIntegrityRun(successfulRun(overrides), expected),
      /does not prove a successful exact-source gate/u,
    );
  });
}

test("fetches only the requested run and validates its live response", async () => {
  let requestedUrl = "";
  let requestedHeaders;
  const run = await fetchAndValidateIntegrityRun({
    ...expected,
    token: "test-token",
    request: async (url, options) => {
      requestedUrl = url;
      requestedHeaders = options.headers;
      return {
        ok: true,
        async text() {
          return JSON.stringify(successfulRun());
        },
      };
    },
  });

  assert.equal(
    requestedUrl,
    "https://api.github.com/repos/Ccatalan7/bikeshop-erp/actions/runs/123456",
  );
  assert.equal(requestedHeaders.Authorization, "Bearer test-token");
  assert.equal(run.head_sha, HEAD_SHA);
});
