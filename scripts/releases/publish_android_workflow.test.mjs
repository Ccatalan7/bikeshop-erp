#!/usr/bin/env node

import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  dispatchWorkflow,
  formatWorkflowFailureSummary,
  findOrDispatchRun,
  loadPreparedState,
  main,
  validateAndroidManifest,
} from "./publish_android_workflow.mjs";

const FROM_COMMIT = "1".repeat(40);
const TO_COMMIT = "2".repeat(40);

function manifest() {
  const apkObjectPath =
    "5443b130-cc28-45af-a420-cd500b288890/android/releases/" +
    "vinabike-erp-1.0.1+42-arm64-v8a.apk";
  return {
    schema_version: 1,
    package_name: "com.vinabike.erp",
    version_name: "1.0.1",
    build_number: 42,
    version_code: 2042,
    apk_object_path: apkObjectPath,
    sha256: "a".repeat(64),
    size_bytes: 100,
    apk_parts: [
      {
        object_path: `${apkObjectPath}.part000`,
        sha256: "b".repeat(64),
        size_bytes: 100,
      },
    ],
    published_at: "2026-07-26T12:00:00Z",
    commit: TO_COMMIT,
    release_notes: {
      schema_version: 1,
      locale: "es-CL",
      source: "ai",
      from_commit: FROM_COMMIT,
      to_commit: TO_COMMIT,
      title: "Novedades de esta actualización",
      summary: "Ahora es más fácil trabajar desde el ERP.",
      modules: [
        {
          id: "general",
          label: "General",
          items: ["Se mejoró la experiencia de actualización."],
          evidence_paths: ["lib/main.dart"],
        },
      ],
    },
  };
}

test("accepts exact Android publication evidence with structured notes", () => {
  const validated = validateAndroidManifest(manifest(), TO_COMMIT, FROM_COMMIT);
  assert.equal(validated.build_number, 42);
  assert.equal(validated.version_code, 2042);
});

test("rejects a manifest that publishes the logical build as the APK code", () => {
  const candidate = manifest();
  candidate.version_code = candidate.build_number;
  assert.throws(
    () => validateAndroidManifest(candidate, TO_COMMIT, FROM_COMMIT),
    /does not match the requested release/u,
  );
});

test("rejects an APK path that is not bound to the logical build number", () => {
  const candidate = manifest();
  candidate.apk_object_path = candidate.apk_object_path.replace("+42-", "+43-");
  candidate.apk_parts[0].object_path = `${candidate.apk_object_path}.part000`;
  assert.throws(
    () => validateAndroidManifest(candidate, TO_COMMIT, FROM_COMMIT),
    /does not match the requested release/u,
  );
});

test("rejects evidence from another source commit", () => {
  assert.throws(
    () => validateAndroidManifest(manifest(), "3".repeat(40), FROM_COMMIT),
    /does not match the requested release/u,
  );
});

test("rejects structured notes that are not bound to the APK commit", () => {
  const candidate = manifest();
  candidate.release_notes.to_commit = "4".repeat(40);
  assert.throws(
    () => validateAndroidManifest(candidate, TO_COMMIT, FROM_COMMIT),
    /invalid structured release notes/u,
  );
});

test("rejects structured notes from another prepared baseline", () => {
  assert.throws(
    () => validateAndroidManifest(manifest(), TO_COMMIT, "9".repeat(40)),
    /invalid structured release notes/u,
  );
});

test("invalid CLI arguments fail without invoking a publication", async () => {
  let stderr = "";
  const exitCode = await main({
    argv: ["--unexpected"],
    stdout: { write() {} },
    stderr: {
      write(value) {
        stderr += value;
      },
    },
  });
  assert.equal(exitCode, 1);
  assert.match(stderr, /Usage:/u);
});

test("dispatch JSON uses only string workflow inputs", () => {
  let captured;
  dispatchWorkflow(
    {
      repositoryRoot: "/repo",
      branch: "smartpegas1.0",
      headSha: TO_COMMIT,
      releaseNotesFromCommit: FROM_COMMIT,
      releaseNotesCandidateBase64: "e30=",
      releaseNotesCandidateSha256: "a".repeat(64),
      integrityRunId: "123456",
      integrityRunAttempt: "2",
    },
    (command, args, options) => {
      captured = { command, args, options };
      return "";
    },
  );

  assert.equal(captured.command, "gh");
  assert.deepEqual(captured.args.slice(0, 3), [
    "workflow",
    "run",
    "macos-release.yml",
  ]);
  const payload = JSON.parse(captured.options.input);
  assert.deepEqual(
    Object.values(payload).map((value) => typeof value),
    [
      "string",
      "string",
      "string",
      "string",
      "string",
      "string",
      "string",
      "string",
    ],
  );
  assert.equal(payload.release_target, "android");
  assert.equal(payload.publish_release, "true");
  assert.equal(payload.integrity_run_id, "123456");
  assert.equal(payload.integrity_run_attempt, "2");
});

test("loads a schema-3 state only when its qualification is fully bound", async () => {
  const temporaryRoot = await mkdtemp(
    path.join(os.tmpdir(), "vinabike-android-state-test-"),
  );
  const gitDirectory = path.join(temporaryRoot, ".git");
  await mkdir(gitDirectory);
  const statePath = path.join(gitDirectory, "vinabike-erp-publish-state.json");
  const state = {
    schema_version: 3,
    targets: ["macos", "android"],
    repository_root: temporaryRoot,
    remote: "origin",
    branch: "smartpegas1.0",
    head_sha: TO_COMMIT,
    created_epoch: 1000,
    release_notes: {
      from_commit: FROM_COMMIT,
      candidate_b64: "",
      candidate_sha256: "",
    },
    qualification: {
      repository: "Ccatalan7/bikeshop-erp",
      workflow_path: ".github/workflows/erp-integrity-gate.yml",
      workflow_id: 99,
      run_id: 123456,
      run_attempt: 2,
      head_sha: TO_COMMIT,
      branch: "smartpegas1.0",
      completed_at: "2026-07-31T18:05:00Z",
    },
  };
  await writeFile(statePath, JSON.stringify(state));
  const run = (command, args) => {
    assert.equal(command, "git");
    if (args[1] === "--show-toplevel") return temporaryRoot;
    if (args[1] === "--absolute-git-dir") return gitDirectory;
    throw new Error(`Unexpected git arguments: ${args.join(" ")}`);
  };

  try {
    const loaded = await loadPreparedState({
      repoDir: temporaryRoot,
      nowEpoch: 1001,
      run,
    });
    assert.equal(loaded.integrityWorkflowId, "99");
    assert.equal(loaded.integrityRunId, "123456");
    assert.equal(loaded.integrityRunAttempt, "2");

    state.qualification.head_sha = "3".repeat(40);
    await writeFile(statePath, JSON.stringify(state));
    await assert.rejects(
      loadPreparedState({
        repoDir: temporaryRoot,
        nowEpoch: 1001,
        run,
      }),
      /qualification is malformed or stale/u,
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test("reuses a completed successful exact-title Android run", async () => {
  const state = {
    repositoryRoot: "/repo",
    branch: "smartpegas1.0",
    headSha: TO_COMMIT,
    releaseNotesFromCommit: FROM_COMMIT,
    releaseNotesCandidateSha256: "a".repeat(64),
    integrityRunId: "123456",
  };
  let dispatchCount = 0;
  const existing = {
    databaseId: 88,
    headSha: TO_COMMIT,
    status: "completed",
    conclusion: "success",
    createdAt: "2026-07-31T18:05:00Z",
    displayTitle:
      `Android publish · ${TO_COMMIT} · notes ${"a".repeat(64)} · ` +
      `from ${FROM_COMMIT} · integrity 123456`,
  };
  const selected = await findOrDispatchRun(state, {
    run(command, args) {
      if (args[0] === "run" && args[1] === "list") {
        return JSON.stringify([existing]);
      }
      if (args[0] === "workflow") {
        dispatchCount += 1;
        return "";
      }
      throw new Error(`Unexpected command: ${command} ${args.join(" ")}`);
    },
  });

  assert.equal(selected.databaseId, 88);
  assert.equal(dispatchCount, 0);
});

test("nested workflow diagnostics end with the exact Flutter gate summary", () => {
  const jobsJson = JSON.stringify({
    jobs: [
      {
        name:
          "Route to independently protected Android release / " +
          "Verify application integrity / Application regression gate",
        conclusion: "failure",
        steps: [
          {
            name: "Run all Flutter tests",
            conclusion: "failure",
          },
        ],
      },
    ],
  });
  const prefix = "nested workflow\tUNKNOWN STEP\t2026-07-27T07:17:10.5827557Z ";
  const failedLog = [
    `${prefix}[flutter-test-gate] Flutter tests failed. Exact failure summary:`,
    `${prefix}`,
    `${prefix}FAILED: user console honors the employee-linking action contract`,
    `${prefix}  File: test/unit/example_test.dart:198:3`,
    `${prefix}  Expected: contains 'healthy link'`,
    `${prefix}  At: test/unit/example_test.dart 223:5 main.<fn>`,
    `${prefix}`,
    `${prefix}[flutter-test-gate] Nothing was published. Fix the failure above and run the task again.`,
    `${prefix}Post job cleanup.`,
  ].join("\n");

  const summary = formatWorkflowFailureSummary(jobsJson, failedLog);

  assert.match(
    summary,
    /Failed job: Route to independently protected Android release/u,
  );
  assert.match(summary, /Failed step: Run all Flutter tests/u);
  assert.doesNotMatch(summary, /UNKNOWN STEP/u);
  assert.match(summary, /FAILED: user console honors/u);
  assert.ok(
    summary.endsWith(
      "[flutter-test-gate] Nothing was published. " +
        "Fix the failure above and run the task again.",
    ),
  );
});

test("workflow diagnostics fail safely when GitHub has no gate summary", () => {
  const summary = formatWorkflowFailureSummary("not-json", "");

  assert.match(summary, /Failed job: unavailable from GitHub jobs API/u);
  assert.ok(
    summary.endsWith(
      "[android-update] Nothing was published. " +
        "Fix the failed step above and run the task again.",
    ),
  );
});
