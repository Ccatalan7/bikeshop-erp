import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const script = path.join(repoRoot, "scripts/dev/visual_compare.py");

function run(args) {
  return new Promise((resolve, reject) => {
    const child = spawn("python3", [script, ...args], {
      cwd: repoRoot,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code, stdout, stderr }));
  });
}

test("columns with a missing band endpoint exits with clean usage", async () => {
  const result = await run(["columns", "unused.png", "--band", "10"]);

  assert.notEqual(result.code, 0);
  assert.match(
    result.stderr,
    /uso: visual_compare\.py columns <png> --band Y0 Y1/,
  );
  assert.doesNotMatch(result.stderr, /Traceback|IndexError/);
});
