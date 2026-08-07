#!/usr/bin/env node

import assert from "node:assert/strict";
import test from "node:test";

import {
  awaitIntegrityQualification,
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

// Esperar a un gate en vuelo es lo que permite despachar los publicadores
// mientras el gate corre. Un run no concluido no es un run fallido; uno que
// nunca concluye dentro del presupuesto sí se rechaza.
function respondWith(sequence) {
  let call = 0;
  return async () => {
    const body = JSON.stringify(sequence[Math.min(call++, sequence.length - 1)]);
    return { ok: true, text: async () => body };
  };
}

test("waits for an in-flight gate and accepts its success", async () => {
  const slept = [];
  const run = await awaitIntegrityQualification({
    ...expected,
    token: "t",
    request: respondWith([
      successfulRun({ status: "queued", conclusion: null }),
      successfulRun({ status: "in_progress", conclusion: null }),
      successfulRun(),
    ]),
    waitSeconds: 600,
    pollSeconds: 1,
    sleep: async (ms) => slept.push(ms),
  });
  assert.equal(run.id, 123456);
  assert.deepEqual(slept, [1000, 1000]);
});

test("rejects a gate that never concludes within the budget", async () => {
  let clock = 0;
  await assert.rejects(
    awaitIntegrityQualification({
      ...expected,
      token: "t",
      request: respondWith([successfulRun({ status: "in_progress", conclusion: null })]),
      waitSeconds: 5,
      pollSeconds: 1,
      sleep: async () => {
        clock += 4000;
      },
      now: () => clock,
    }),
    /does not prove a successful/u,
  );
});

test("a concluded failure is never retried into success", async () => {
  const slept = [];
  await assert.rejects(
    awaitIntegrityQualification({
      ...expected,
      token: "t",
      request: respondWith([
        successfulRun({ conclusion: "failure" }),
        successfulRun(),
      ]),
      waitSeconds: 600,
      pollSeconds: 1,
      sleep: async (ms) => slept.push(ms),
    }),
    /does not prove a successful/u,
  );
  assert.deepEqual(slept, []);
});
