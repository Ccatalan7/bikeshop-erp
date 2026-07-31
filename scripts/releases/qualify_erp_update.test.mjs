#!/usr/bin/env node

import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  chooseExactQualificationRun,
  findOrDispatchQualificationRun,
  waitForQualification,
  writeQualification,
} from "./qualify_erp_update.mjs";

const HEAD_SHA = "a".repeat(40);

function gateRun({
  id,
  status = "completed",
  conclusion = "success",
  headSha = HEAD_SHA,
  event = "push",
  createdAt = "2026-07-31T18:00:00Z",
} = {}) {
  return {
    databaseId: id,
    attempt: 1,
    status,
    conclusion,
    headSha,
    event,
    createdAt,
    workflowName: "ERP Integrity Gate",
    url: `https://github.test/actions/runs/${id}`,
  };
}

function prepared() {
  return {
    repositoryRoot: "/repo",
    state: {
      branch: "smartpegas1.0",
      head_sha: HEAD_SHA,
      remote: "origin",
    },
  };
}

function commandStub(listResponses) {
  const calls = [];
  return {
    calls,
    run(command, args, options = {}) {
      calls.push({ command, args, options });
      if (command === "gh" && args[0] === "run" && args[1] === "list") {
        return JSON.stringify(listResponses.shift() ?? []);
      }
      if (command === "gh" && args[0] === "workflow") return "";
      if (command === "git" && args[0] === "ls-remote") {
        return `${HEAD_SHA}\trefs/heads/smartpegas1.0`;
      }
      throw new Error(`Unexpected command: ${command} ${args.join(" ")}`);
    },
  };
}

test("prefers a completed successful exact-SHA run", () => {
  const chosen = chooseExactQualificationRun(
    [
      gateRun({ id: 1, conclusion: "failure" }),
      gateRun({ id: 2, status: "in_progress", conclusion: null }),
      gateRun({ id: 3, createdAt: "2026-07-31T18:01:00Z" }),
      gateRun({ id: 4, headSha: "b".repeat(40) }),
    ],
    HEAD_SHA,
  );
  assert.equal(chosen.databaseId, 3);
});

test("reuses a queued exact-SHA push run without dispatching", async () => {
  const stub = commandStub([
    [gateRun({ id: 10, status: "queued", conclusion: null })],
  ]);
  const result = await findOrDispatchQualificationRun(prepared(), {
    run: stub.run,
    wait: async () => {},
    discoveryTimeoutMs: 0,
    pollIntervalMs: 1,
  });

  assert.equal(result.dispatched, false);
  assert.equal(result.workflowRun.databaseId, 10);
  assert.equal(
    stub.calls.filter((call) => call.args[0] === "workflow").length,
    0,
  );
});

test("dispatches once when the bounded push-run wait finds nothing", async () => {
  const dispatched = gateRun({
    id: 11,
    status: "queued",
    conclusion: null,
    event: "workflow_dispatch",
  });
  const stub = commandStub([[], [], [dispatched]]);
  const result = await findOrDispatchQualificationRun(prepared(), {
    run: stub.run,
    wait: async () => {},
    discoveryTimeoutMs: 0,
    lookupTimeoutMs: 0,
    pollIntervalMs: 1,
  });

  assert.equal(result.dispatched, true);
  assert.equal(result.workflowRun.databaseId, 11);
  const dispatches = stub.calls.filter(
    (call) => call.args[0] === "workflow" && call.args[1] === "run",
  );
  assert.equal(dispatches.length, 1);
  assert.deepEqual(JSON.parse(dispatches[0].options.input), {
    expected_commit: HEAD_SHA,
  });
});

test("a run appearing at the final pre-dispatch lookup is reused", async () => {
  const lastMoment = gateRun({
    id: 12,
    status: "pending",
    conclusion: null,
  });
  const stub = commandStub([[], [lastMoment]]);
  const result = await findOrDispatchQualificationRun(prepared(), {
    run: stub.run,
    wait: async () => {},
    discoveryTimeoutMs: 0,
    pollIntervalMs: 1,
  });

  assert.equal(result.dispatched, false);
  assert.equal(result.workflowRun.databaseId, 12);
  assert.equal(
    stub.calls.filter((call) => call.args[0] === "workflow").length,
    0,
  );
});

test("a branch move after preparation prevents fallback dispatch", async () => {
  const stub = commandStub([[], []]);
  const originalRun = stub.run;
  stub.run = (command, args, options) => {
    if (command === "git" && args[0] === "ls-remote") {
      return `${"b".repeat(40)}\trefs/heads/smartpegas1.0`;
    }
    return originalRun(command, args, options);
  };

  await assert.rejects(
    findOrDispatchQualificationRun(prepared(), {
      run: stub.run,
      wait: async () => {},
      discoveryTimeoutMs: 0,
      pollIntervalMs: 1,
    }),
    /live branch moved/u,
  );
  assert.equal(
    stub.calls.filter((call) => call.args[0] === "workflow").length,
    0,
  );
});

test("returns a completed same-SHA failure for immediate diagnosis", async () => {
  const failed = gateRun({ id: 13, conclusion: "failure" });
  const stub = commandStub([[failed]]);
  const result = await findOrDispatchQualificationRun(prepared(), {
    run: stub.run,
    wait: async () => {},
    discoveryTimeoutMs: 0,
    pollIntervalMs: 1,
  });

  assert.equal(result.dispatched, false);
  assert.equal(result.workflowRun.conclusion, "failure");
});

function liveRun({ attempt, status, conclusion }) {
  return {
    id: 20,
    run_attempt: attempt,
    workflow_id: 99,
    name: "ERP Integrity Gate",
    path: ".github/workflows/erp-integrity-gate.yml",
    event: "push",
    head_sha: HEAD_SHA,
    head_branch: "smartpegas1.0",
    status,
    conclusion,
    repository: { full_name: "Ccatalan7/bikeshop-erp" },
    head_repository: { full_name: "Ccatalan7/bikeshop-erp" },
    updated_at: "2026-07-31T18:05:00Z",
  };
}

test("retries one transient same-run failure but never dispatches another run", async () => {
  const responses = [
    liveRun({ attempt: 1, status: "completed", conclusion: "timed_out" }),
    liveRun({ attempt: 1, status: "completed", conclusion: "timed_out" }),
    liveRun({ attempt: 2, status: "in_progress", conclusion: null }),
    liveRun({ attempt: 2, status: "completed", conclusion: "success" }),
  ];
  const calls = [];
  const result = await waitForQualification(
    prepared(),
    { databaseId: 20, attempt: 1 },
    {
      wait: async () => {},
      pollIntervalMs: 1,
      timeoutMs: 10,
      run(command, args) {
        calls.push({ command, args });
        if (args[0] === "api") return JSON.stringify(responses.shift());
        if (args[0] === "run" && args[1] === "rerun") return "";
        throw new Error(`Unexpected command: ${command} ${args.join(" ")}`);
      },
    },
  );

  assert.equal(result.run_attempt, 2);
  assert.equal(
    calls.filter((call) => call.args[0] === "run" && call.args[1] === "rerun")
      .length,
    1,
  );
  assert.equal(calls.filter((call) => call.args[0] === "workflow").length, 0);
});

test("atomically upgrades schema 2 with the complete bound proof", async () => {
  const temporaryDirectory = await mkdtemp(
    path.join(os.tmpdir(), "vinabike-qualification-state-test-"),
  );
  const statePath = path.join(temporaryDirectory, "state.json");
  const state = {
    schema_version: 2,
    targets: ["macos", "android"],
    branch: "smartpegas1.0",
    head_sha: HEAD_SHA,
  };
  await writeFile(statePath, `${JSON.stringify(state)}\n`);
  const live = liveRun({
    attempt: 2,
    status: "completed",
    conclusion: "success",
  });
  try {
    await writeQualification({ statePath, state }, live);
    const written = JSON.parse(await readFile(statePath, "utf8"));
    assert.equal(written.schema_version, 3);
    assert.deepEqual(written.qualification, {
      repository: "Ccatalan7/bikeshop-erp",
      workflow_path: ".github/workflows/erp-integrity-gate.yml",
      workflow_id: 99,
      run_id: 20,
      run_attempt: 2,
      head_sha: HEAD_SHA,
      branch: "smartpegas1.0",
      completed_at: "2026-07-31T18:05:00Z",
    });
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});

test("does not rerun an application-test failure for the same SHA", async () => {
  const calls = [];
  await assert.rejects(
    waitForQualification(
      prepared(),
      { databaseId: 20, attempt: 1 },
      {
        wait: async () => {},
        pollIntervalMs: 1,
        timeoutMs: 1,
        run(command, args) {
          calls.push({ command, args });
          if (args[0] === "api" && args.includes("/jobs")) {
            return JSON.stringify({ jobs: [] });
          }
          if (args[0] === "api") {
            return JSON.stringify(
              liveRun({
                attempt: 1,
                status: "completed",
                conclusion: "failure",
              }),
            );
          }
          if (args[0] === "run" && args[1] === "view") return "";
          throw new Error(`Unexpected command: ${command} ${args.join(" ")}`);
        },
      },
    ),
    /Fix that exact failure before publishing/u,
  );
  assert.equal(
    calls.filter((call) => call.args[0] === "run" && call.args[1] === "rerun")
      .length,
    0,
  );
});
