#!/usr/bin/env node

import assert from "node:assert/strict";
import test from "node:test";

import {
  dispatchWorkflow,
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
    version_code: 42,
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
  assert.equal(validateAndroidManifest(manifest(), TO_COMMIT).version_code, 42);
});

test("rejects evidence from another source commit", () => {
  assert.throws(
    () => validateAndroidManifest(manifest(), "3".repeat(40)),
    /does not match the requested release/u,
  );
});

test("rejects structured notes that are not bound to the APK commit", () => {
  const candidate = manifest();
  candidate.release_notes.to_commit = "4".repeat(40);
  assert.throws(
    () => validateAndroidManifest(candidate, TO_COMMIT),
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
  assert.deepEqual(Object.values(payload).map((value) => typeof value), [
    "string",
    "string",
    "string",
    "string",
    "string",
    "string",
  ]);
  assert.equal(payload.release_target, "android");
  assert.equal(payload.publish_release, "true");
});
