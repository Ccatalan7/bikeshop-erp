#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

test("generic widget failures include the bounded same-test framework exception", async () => {
  const temporaryDirectory = await mkdtemp(
    path.join(os.tmpdir(), "vinabike-flutter-gate-test-"),
  );
  const fakeFlutter = path.join(temporaryDirectory, "fake-flutter");
  const events = [
    {
      type: "testStart",
      test: {
        id: 1,
        name: "a pre-RPC save failure rebuilds the retry",
        url: "file:///repo/test/widgets/checkout_durable_recovery_widget_test.dart",
        line: 253,
        column: 3,
      },
    },
    {
      type: "print",
      testID: 2,
      message:
        "══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞══\n" +
        "UNRELATED SECRET DIAGNOSTIC",
    },
    {
      type: "print",
      testID: 1,
      message:
        "══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞══\n" +
        "Expected: exactly one matching candidate\n" +
        "  Actual: Found 0 widgets with text confirmation:order-retry\n" +
        "test/widgets/checkout_durable_recovery_widget_test.dart 386:5",
    },
    {
      type: "error",
      testID: 1,
      error: "Test failed. See exception logs above.",
      stackTrace: "package:flutter_test/src/widget_tester.dart 1:1 fail",
      isFailure: true,
    },
  ];
  const script = [
    "#!/bin/bash",
    'if [[ "$1" != "test" || "$2" != "--machine" ]]; then exit 90; fi',
    ...events.map(
      (event) =>
        `printf '%s\\n' '${JSON.stringify(event).replaceAll("'", "'\\''")}'`,
    ),
    "exit 1",
    "",
  ].join("\n");

  try {
    await writeFile(fakeFlutter, script, "utf8");
    await chmod(fakeFlutter, 0o700);
    const result = spawnSync(
      "bash",
      ["scripts/run_flutter_test_gate.sh", fakeFlutter],
      { cwd: process.cwd(), encoding: "utf8" },
    );

    assert.equal(result.status, 1);
    assert.match(result.stderr, /Expected: exactly one matching candidate/u);
    assert.match(result.stderr, /Actual: Found 0 widgets/u);
    assert.match(result.stderr, /confirmation:order-retry/u);
    assert.match(
      result.stderr,
      /checkout_durable_recovery_widget_test\.dart 386:5/u,
    );
    assert.doesNotMatch(result.stderr, /UNRELATED SECRET DIAGNOSTIC/u);
    assert.ok(result.stderr.length < 6000);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
});
