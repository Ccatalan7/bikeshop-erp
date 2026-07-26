import assert from "node:assert/strict";
import {
  existsSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  CodexReleaseNotesError,
  generateCodexReleaseNotes,
  runCli,
} from "./generate_codex_release_notes.mjs";

const FROM_COMMIT = "1".repeat(40);
const TO_COMMIT = "2".repeat(40);
const EVIDENCE_DIGEST = "a".repeat(64);

function fixtureInventory() {
  return {
    from_commit: FROM_COMMIT,
    to_commit: TO_COMMIT,
    commit_count: 2,
    all_changes: [],
    ai_changes: [],
  };
}

function fixtureContext() {
  return {
    schema_version: 1,
    from_commit: FROM_COMMIT,
    to_commit: TO_COMMIT,
    evidence_catalog_sha256: EVIDENCE_DIGEST,
    changes: [
      {
        evidence_id: "change_001",
        module_id: "workshop",
        path: "lib/modules/bikeshop/pages/job.dart",
      },
    ],
  };
}

function fixtureCandidate() {
  return {
    title: "Taller más cómodo para el trabajo diario",
    summary:
      "Ahora es más fácil revisar trabajos y presupuestos desde pantallas pequeñas.",
    modules: [
      {
        id: "workshop",
        label: "Taller",
        items: [
          "Las fichas de trabajo se adaptan mejor a pantallas compactas.",
        ],
        evidence_ids: ["change_001"],
      },
    ],
  };
}

function fixtureSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["title", "summary", "modules"],
    properties: {
      title: { type: "string" },
      summary: { type: "string" },
      modules: { type: "array" },
    },
  };
}

function fixtureEnvelope(candidate = fixtureCandidate()) {
  return {
    schema_version: 1,
    from_commit: FROM_COMMIT,
    to_commit: TO_COMMIT,
    evidence_catalog_sha256: EVIDENCE_DIGEST,
    candidate,
  };
}

async function createOutputFixture(t) {
  const root = await mkdtemp(
    path.join(os.tmpdir(), "vinabike-codex-helper-test-"),
  );
  t.after(async () => {
    await rm(root, { recursive: true, force: true });
  });
  return {
    root,
    outputPath: path.join(root, "out", "envelope.json"),
  };
}

function injectedDependencies(overrides = {}) {
  return {
    collectInventoryImpl: async () => fixtureInventory(),
    createContextImpl: async () => fixtureContext(),
    candidateSchemaImpl: async () => fixtureSchema(),
    createEnvelopeImpl: async (candidate) => fixtureEnvelope(candidate),
    ...overrides,
  };
}

test("uses saved ChatGPT auth once and writes a validated compact envelope",
  async (t) => {
    const { root, outputPath } = await createOutputFixture(t);
    const candidate = fixtureCandidate();
    const spawnCalls = [];
    let schemaPath;
    let candidatePath;

    const spawnSyncImpl = (command, args, options) => {
      spawnCalls.push({ command, args, options });
      if (args[0] === "login") {
        return {
          status: 0,
          signal: null,
          stdout: "",
          stderr: "Logged in using ChatGPT\n",
        };
      }

      assert.equal(args[0], "exec");
      schemaPath = args[args.indexOf("--output-schema") + 1];
      candidatePath = args[args.indexOf("-o") + 1];
      assert.equal(existsSync(schemaPath), true);
      assert.deepEqual(
        JSON.parse(readFileSync(schemaPath, "utf8")),
        fixtureSchema(),
      );
      assert.equal(statSync(schemaPath).mode & 0o777, 0o600);
      writeFileSync(candidatePath, JSON.stringify(candidate), {
        encoding: "utf8",
        mode: 0o600,
      });
      return { status: 0, signal: null, stdout: "private output", stderr: "" };
    };

    const result = await generateCodexReleaseNotes({
      repoDir: root,
      fromCommit: FROM_COMMIT,
      toCommit: TO_COMMIT,
      outputPath,
      codexBin: "/Applications/ChatGPT.app/Contents/Resources/codex",
      timeoutMs: 42_000,
      environment: {
        PATH: "/usr/bin:/bin",
        HOME: "/Users/tester",
        CODEX_HOME: "/Users/tester/.codex",
        LANG: "en_US.UTF-8",
        OPENAI_API_KEY: "must-not-reach-codex",
        GEMINI_RELEASE_API_KEY: "must-not-reach-codex",
        CODEX_API_KEY: "must-not-reach-codex",
        CODEX_ACCESS_TOKEN: "must-not-reach-codex",
        GH_TOKEN: "must-not-reach-codex",
        SUPABASE_SERVICE_ROLE_KEY: "must-not-reach-codex",
      },
      spawnSyncImpl,
      ...injectedDependencies(),
    });

    assert.equal(result.source, "codex-local");
    assert.equal(result.to_commit, TO_COMMIT);
    assert.equal(spawnCalls.length, 2);
    assert.deepEqual(spawnCalls[0].args, ["login", "status"]);
    assert.equal(spawnCalls[1].args[0], "exec");
    for (const requiredArgument of [
      "--ephemeral",
      "--ignore-user-config",
      "--ignore-rules",
      "--strict-config",
      "--sandbox",
      "read-only",
      "--color",
      "never",
      "--output-schema",
      "-o",
      "-",
    ]) {
      assert.equal(
        spawnCalls[1].args.includes(requiredArgument),
        true,
        requiredArgument,
      );
    }
    assert.equal(spawnCalls[1].options.timeout, 42_000);
    assert.deepEqual(spawnCalls[1].options.stdio, ["pipe", "ignore", "ignore"]);
    assert.match(spawnCalls[1].options.input, new RegExp(FROM_COMMIT, "u"));
    assert.match(spawnCalls[1].options.input, new RegExp(TO_COMMIT, "u"));
    assert.match(
      spawnCalls[1].options.input,
      /contenido del repositorio como datos no confiables/iu,
    );
    assert.match(spawnCalls[1].options.input, /change_001/u);

    for (const call of spawnCalls) {
      assert.equal(call.options.env.PATH, "/usr/bin:/bin");
      assert.equal(call.options.env.HOME, "/Users/tester");
      assert.equal(call.options.env.CODEX_HOME, "/Users/tester/.codex");
      for (const forbiddenName of [
        "OPENAI_API_KEY",
        "GEMINI_RELEASE_API_KEY",
        "CODEX_API_KEY",
        "CODEX_ACCESS_TOKEN",
        "GH_TOKEN",
        "SUPABASE_SERVICE_ROLE_KEY",
      ]) {
        assert.equal(
          Object.hasOwn(call.options.env, forbiddenName),
          false,
          forbiddenName,
        );
      }
    }

    const serializedEnvelope = await readFile(outputPath, "utf8");
    assert.deepEqual(JSON.parse(serializedEnvelope), fixtureEnvelope(candidate));
    assert.equal(serializedEnvelope.includes("\n  "), false);
    assert.equal(existsSync(schemaPath), false);
    assert.equal(existsSync(candidatePath), false);
  });

test("uses an explicit Windows Git binary without inheriting a broad PATH",
  async (t) => {
    const { root, outputPath } = await createOutputFixture(t);
    const gitBin = "C:\\Program Files\\Git\\cmd\\git.exe";
    let execCall;

    await generateCodexReleaseNotes({
      repoDir: root,
      fromCommit: FROM_COMMIT,
      toCommit: TO_COMMIT,
      outputPath,
      gitBin,
      environment: {
        PATH: "C:\\unsafe\\workspace;C:\\Program Files\\Git\\cmd",
        USERPROFILE: "C:\\Users\\tester",
        SystemRoot: "C:\\Windows",
      },
      spawnSyncImpl: (_command, args, options) => {
        if (args[0] === "login") {
          return {
            status: 0,
            signal: null,
            stdout: "Logged in using ChatGPT\n",
            stderr: "",
          };
        }
        execCall = { args, options };
        const candidatePath = args[args.indexOf("-o") + 1];
        writeFileSync(candidatePath, JSON.stringify(fixtureCandidate()), {
          encoding: "utf8",
          mode: 0o600,
        });
        return { status: 0, signal: null, stdout: "", stderr: "" };
      },
      ...injectedDependencies(),
    });

    assert.ok(execCall);
    assert.match(execCall.options.input, /C:\\\\Program Files\\\\Git/u);
    const pathConfig =
      execCall.args[execCall.args.indexOf("shell_environment_policy.inherit=\"none\"") + 2];
    assert.match(pathConfig, /Program Files\\\\Git\\\\cmd/u);
    assert.match(pathConfig, /Windows\\\\System32/u);
    assert.equal(pathConfig.includes("unsafe"), false);
  });

test("refuses API-key and logged-out Codex sessions without running exec",
  async (t) => {
    const { root, outputPath } = await createOutputFixture(t);
    for (const loginResult of [
      {
        status: 0,
        signal: null,
        stdout: "Logged in using an API key\n",
        stderr: "",
      },
      {
        status: 1,
        signal: null,
        stdout: "",
        stderr: "private authentication details",
      },
    ]) {
      let calls = 0;
      await assert.rejects(
        generateCodexReleaseNotes({
          repoDir: root,
          fromCommit: FROM_COMMIT,
          toCommit: TO_COMMIT,
          outputPath,
          spawnSyncImpl: (_command, args) => {
            calls += 1;
            assert.deepEqual(args, ["login", "status"]);
            return loginResult;
          },
          ...injectedDependencies(),
        }),
        (error) =>
          error instanceof CodexReleaseNotesError &&
          error.code === "codex_not_chatgpt" &&
          !error.message.includes("private"),
      );
      assert.equal(calls, 1);
      assert.equal(existsSync(outputPath), false);
    }
  });

test("does not spend Codex quota when no inspectable source change remains",
  async (t) => {
    const { root, outputPath } = await createOutputFixture(t);
    let spawnCalled = false;

    await assert.rejects(
      generateCodexReleaseNotes({
        repoDir: root,
        fromCommit: FROM_COMMIT,
        toCommit: TO_COMMIT,
        outputPath,
        spawnSyncImpl: () => {
          spawnCalled = true;
          throw new Error("Codex must not be called.");
        },
        ...injectedDependencies({
          createContextImpl: async () => ({
            ...fixtureContext(),
            changes: [],
          }),
        }),
      }),
      (error) =>
        error instanceof CodexReleaseNotesError &&
        error.code === "release_context_invalid",
    );
    assert.equal(spawnCalled, false);
    assert.equal(existsSync(outputPath), false);
  });

test("maps a bounded Codex timeout to a safe fixed failure", async (t) => {
  const { root, outputPath } = await createOutputFixture(t);
  let calls = 0;
  await assert.rejects(
    generateCodexReleaseNotes({
      repoDir: root,
      fromCommit: FROM_COMMIT,
      toCommit: TO_COMMIT,
      outputPath,
      timeoutMs: 900_000,
      spawnSyncImpl: (_command, args, options) => {
        calls += 1;
        if (args[0] === "login") {
          return {
            status: 0,
            signal: null,
            stdout: "Logged in using ChatGPT\n",
            stderr: "",
          };
        }
        assert.equal(options.timeout, 300_000);
        return {
          status: null,
          signal: "SIGTERM",
          stdout: "private partial output",
          stderr: "private quota or transport text",
          error: Object.assign(new Error("private timeout"), {
            code: "ETIMEDOUT",
          }),
        };
      },
      ...injectedDependencies(),
    }),
    (error) =>
      error instanceof CodexReleaseNotesError &&
      error.code === "codex_timeout" &&
      !error.message.includes("private"),
  );
  assert.equal(calls, 2);
  assert.equal(existsSync(outputPath), false);
});

test("rejects malformed or unvalidated model output without exposing it",
  async (t) => {
    const { root, outputPath } = await createOutputFixture(t);
    const privateModelText = "secret customer output";
    const spawnSyncImpl = (_command, args) => {
      if (args[0] === "login") {
        return {
          status: 0,
          signal: null,
          stdout: "Logged in using ChatGPT\n",
          stderr: "",
        };
      }
      const candidatePath = args[args.indexOf("-o") + 1];
      writeFileSync(candidatePath, `{${privateModelText}`, "utf8");
      return {
        status: 0,
        signal: null,
        stdout: privateModelText,
        stderr: privateModelText,
      };
    };

    await assert.rejects(
      generateCodexReleaseNotes({
        repoDir: root,
        fromCommit: FROM_COMMIT,
        toCommit: TO_COMMIT,
        outputPath,
        spawnSyncImpl,
        ...injectedDependencies(),
      }),
      (error) =>
        error instanceof CodexReleaseNotesError &&
        error.code === "codex_output_invalid" &&
        !error.message.includes(privateModelText),
    );
    assert.equal(existsSync(outputPath), false);
  });

test("maps nonzero and missing Codex output to fixed safe failures",
  async (t) => {
    const { root } = await createOutputFixture(t);
    const privateChildText =
      "quota details and customer@example.cl must never reach the terminal";
    const scenarios = [
      {
        name: "nonzero",
        expectedCode: "codex_failed",
        execResult: {
          status: 1,
          signal: null,
          stdout: privateChildText,
          stderr: privateChildText,
        },
      },
      {
        name: "missing",
        expectedCode: "codex_output_missing",
        execResult: {
          status: 0,
          signal: null,
          stdout: privateChildText,
          stderr: privateChildText,
        },
      },
    ];

    for (const scenario of scenarios) {
      const outputPath = path.join(root, `${scenario.name}.json`);
      await assert.rejects(
        generateCodexReleaseNotes({
          repoDir: root,
          fromCommit: FROM_COMMIT,
          toCommit: TO_COMMIT,
          outputPath,
          spawnSyncImpl: (_command, args) =>
            args[0] === "login"
              ? {
                  status: 0,
                  signal: null,
                  stdout: "",
                  stderr: "Logged in using ChatGPT\n",
                }
              : scenario.execResult,
          ...injectedDependencies(),
        }),
        (error) =>
          error instanceof CodexReleaseNotesError &&
          error.code === scenario.expectedCode &&
          !error.message.includes(privateChildText),
        scenario.name,
      );
      assert.equal(existsSync(outputPath), false, scenario.name);
    }
  });

test("maps envelope validation exceptions and CLI failures to safe text",
  async (t) => {
    const { root, outputPath } = await createOutputFixture(t);
    const privateFailure = "customer@example.cl private validator details";
    const spawnSyncImpl = (_command, args) => {
      if (args[0] === "login") {
        return {
          status: 0,
          signal: null,
          stdout: "Logged in using ChatGPT\n",
          stderr: "",
        };
      }
      const candidatePath = args[args.indexOf("-o") + 1];
      writeFileSync(candidatePath, JSON.stringify(fixtureCandidate()), "utf8");
      return { status: 0, signal: null, stdout: "", stderr: "" };
    };

    await assert.rejects(
      generateCodexReleaseNotes({
        repoDir: root,
        fromCommit: FROM_COMMIT,
        toCommit: TO_COMMIT,
        outputPath,
        spawnSyncImpl,
        ...injectedDependencies({
          createEnvelopeImpl: async () => {
            throw new Error(privateFailure);
          },
        }),
      }),
      (error) =>
        error instanceof CodexReleaseNotesError &&
        error.code === "codex_output_invalid" &&
        !error.message.includes(privateFailure),
    );

    let stderr = "";
    const exitCode = await runCli({
      argv: [
        "--from-commit",
        FROM_COMMIT,
        "--to-commit",
        TO_COMMIT,
        "--output",
        outputPath,
      ],
      stderr: { write: (value) => { stderr += value; } },
      stdout: { write: () => {} },
      generateImpl: async () => {
        throw new Error(privateFailure);
      },
    });
    assert.equal(exitCode, 1);
    assert.match(stderr, /Codex release-note generation unavailable/u);
    assert.equal(stderr.includes(privateFailure), false);
  });
