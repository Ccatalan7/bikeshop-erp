import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmod, mkdtemp, writeFile } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const script = path.join(repoRoot, "scripts/dev/app_control.sh");

async function makeHarness(t, responder) {
  const temporaryRoot = await mkdtemp(
    path.join(os.tmpdir(), "app-control-test-"),
  );
  const bin = path.join(temporaryRoot, "bin");
  const pgrep = path.join(bin, "pgrep");
  await import("node:fs/promises").then(({ mkdir }) => mkdir(bin));
  await writeFile(pgrep, "#!/bin/sh\necho 4242\n");
  await chmod(pgrep, 0o755);

  let server;
  let log = path.join(temporaryRoot, "native-session.log");
  if (responder) {
    server = http.createServer((request, response) => {
      const url = new URL(request.url, "http://127.0.0.1");
      const payload = responder(url);
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify(payload));
    });
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    t.after(() => new Promise((resolve) => server.close(resolve)));
    const address = server.address();
    const vmUri = `http://127.0.0.1:${address.port}`;
    await writeFile(
      log,
      `Dart VM Service on macOS is available at: ${vmUri}\n`,
    );
  } else {
    await writeFile(log, "");
  }

  const env = {
    ...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    NATIVE_SESSION_LOG: log,
  };
  return { env };
}

function run(args, env) {
  return new Promise((resolve, reject) => {
    const child = spawn("bash", [script, ...args], {
      cwd: repoRoot,
      env,
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
    child.on("close", (code, signal) =>
      resolve({ code, signal, stdout, stderr }),
    );
  });
}

test("identity and read options reject missing values before any RPC", async (t) => {
  const { env } = await makeHarness(t);
  const cases = [
    { args: ["find", "--key"], message: "--key requiere un valor" },
    { args: ["tap", "--label"], message: "--label requiere un valor" },
    {
      args: ["find", "--key", "target", "--index"],
      message: "--index requiere un valor",
    },
    {
      args: ["read", "--filter"],
      message: "uso: app_control.sh read [--filter texto]",
    },
  ];

  for (const { args, message } of cases) {
    const result = await run(args, env);
    assert.equal(result.code, 2, `${args.join(" ")}: ${result.stderr}`);
    assert.match(
      result.stderr,
      new RegExp(message.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")),
    );
  }
});

test("app backend converts physical screenshot coordinates using live DPR", async (t) => {
  const requests = [];
  const { env } = await makeHarness(t, (url) => {
    requests.push({
      path: url.pathname,
      params: Object.fromEntries(url.searchParams),
    });
    if (url.pathname === "/getVM") {
      return { result: { isolates: [{ id: "isolates/1" }] } };
    }
    if (url.pathname === "/getIsolate") {
      return {
        result: {
          extensionRPCs: ["ext.vinabike.input.info", "ext.vinabike.input.tap"],
        },
      };
    }
    if (url.pathname === "/ext.vinabike.input.info") {
      return { result: { ok: true, devicePixelRatio: 2 } };
    }
    if (url.pathname === "/ext.vinabike.input.tap") {
      return { result: { ok: true } };
    }
    throw new Error(`unexpected RPC ${url.pathname}`);
  });

  const result = await run(["click", "200", "120"], env);

  assert.equal(result.code, 0, result.stderr);
  const tap = requests.find(
    (request) => request.path === "/ext.vinabike.input.tap",
  );
  assert.ok(tap, JSON.stringify(requests));
  assert.equal(tap.params.x, "100.0");
  assert.equal(tap.params.y, "60.0");
});

test("identity output treats JSON structurally, not an error word in a label", async (t) => {
  const { env } = await makeHarness(t, (url) => {
    if (url.pathname === "/getVM") {
      return { result: { isolates: [{ id: "isolates/1" }] } };
    }
    if (url.pathname === "/getIsolate") {
      return { result: { extensionRPCs: ["ext.vinabike.input.find"] } };
    }
    if (url.pathname === "/ext.vinabike.input.find") {
      return {
        result: {
          ok: true,
          matches: [
            {
              key: "safe-target",
              label: "Error handling settings",
              widget: "FilledButton",
              centerX: 100,
              centerY: 80,
              width: 120,
              height: 40,
            },
          ],
        },
      };
    }
    throw new Error(`unexpected RPC ${url.pathname}`);
  });

  const result = await run(["find", "--key", "safe-target"], env);

  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /Error handling settings/);
});
