import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  mkdir,
  mkdtemp,
  readFile,
  rename,
  rm,
  unlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  collectReleaseInventory,
  createFallbackReleaseNotes,
  generateReleaseNotes,
  isBinaryReleasePath,
  isGeneratedReleasePath,
  isSensitiveReleasePath,
  moduleForReleasePath,
  validateReleaseNotes,
} from "./generate_release_notes.mjs";

const SCRIPT_PATH = fileURLToPath(
  new URL("./generate_release_notes.mjs", import.meta.url),
);

function runGit(repoDir, args) {
  return execFileSync("git", args, {
    cwd: repoDir,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

async function writeRepoFile(repoDir, relativePath, contents) {
  const target = path.join(repoDir, relativePath);
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, contents);
}

function commit(repoDir, message) {
  runGit(repoDir, ["add", "-A"]);
  runGit(repoDir, ["commit", "-m", message]);
  return runGit(repoDir, ["rev-parse", "HEAD"]);
}

async function createFixtureRepo(t) {
  const repoDir = await mkdtemp(
    path.join(os.tmpdir(), "vinabike-release-notes-test-"),
  );
  t.after(async () => {
    await rm(repoDir, { recursive: true, force: true });
  });

  runGit(repoDir, ["init", "--quiet"]);
  runGit(repoDir, ["config", "user.email", "release-tests@vinabike.local"]);
  runGit(repoDir, ["config", "user.name", "Vinabike Release Tests"]);

  await writeRepoFile(
    repoDir,
    "lib/modules/bikeshop/pages/job.dart",
    "class JobPage {}\n",
  );
  await writeRepoFile(
    repoDir,
    "lib/modules/inventory/old_stock.dart",
    "const oldStock = true;\n",
  );
  await writeRepoFile(repoDir, ".env.production", "TOKEN=old-value\n");
  await writeRepoFile(
    repoDir,
    "web/spreadsheet_engine/univer.bundle.js",
    "generated old bundle\n",
  );
  await writeRepoFile(
    repoDir,
    "assets/private-preview.png",
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00]),
  );
  const fromCommit = commit(repoDir, "Initial desktop release");

  await mkdir(path.join(repoDir, "lib/modules/bikeshop/pages"), {
    recursive: true,
  });
  await rename(
    path.join(repoDir, "lib/modules/bikeshop/pages/job.dart"),
    path.join(repoDir, "lib/modules/bikeshop/pages/quotation.dart"),
  );
  await unlink(path.join(repoDir, "lib/modules/inventory/old_stock.dart"));
  await writeRepoFile(
    repoDir,
    "lib/modules/sales/pages/invoice.dart",
    "class InvoicePage {}\n",
  );
  await writeRepoFile(
    repoDir,
    ".env.production",
    "TOKEN=super-secret-new-value\n",
  );
  await writeRepoFile(
    repoDir,
    "web/spreadsheet_engine/univer.bundle.js",
    "generated new bundle\n",
  );
  await writeRepoFile(
    repoDir,
    "assets/private-preview.png",
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x01, 0x02]),
  );
  const toCommit = commit(
    repoDir,
    "Improve updates token=sk-this-must-never-reach-the-model",
  );

  return { repoDir, fromCommit, toCommit };
}

function responseWithCandidate(candidate) {
  return new Response(
    JSON.stringify({
      output: [
        {
          type: "message",
          content: [
            {
              type: "output_text",
              text: JSON.stringify(candidate),
            },
          ],
        },
      ],
    }),
    {
      status: 200,
      headers: { "content-type": "application/json" },
    },
  );
}

function candidateForInventory(inventory) {
  const evidenceByModule = new Map();
  for (const entry of inventory.ai_changes) {
    if (!evidenceByModule.has(entry.module_id)) {
      evidenceByModule.set(entry.module_id, entry.path);
    }
  }

  const copy = {
    workshop: "Ahora es más claro revisar los trabajos y sus presupuestos.",
    inventory:
      "Mejoramos la estabilidad al revisar la información de inventario.",
    sales: "Mejoramos la experiencia al revisar ventas y pagos.",
    general: "Incluye mejoras generales para un uso más estable.",
  };
  const labels = {
    workshop: "Taller",
    inventory: "Inventario",
    sales: "Ventas y pagos",
    general: "General",
  };

  return {
    title: "Novedades de esta actualización",
    summary:
      "Mejoramos varias herramientas para que el trabajo diario sea más claro.",
    modules: [...evidenceByModule.entries()].map(
      ([moduleId, evidencePath]) => ({
        id: moduleId,
        label: labels[moduleId],
        items: [copy[moduleId]],
        evidence_paths: [evidencePath],
      }),
    ),
  };
}

test("classifies modules and protects sensitive, generated, and binary paths", () => {
  assert.equal(
    moduleForReleasePath("lib/modules/bikeshop/pages/job.dart"),
    "workshop",
  );
  assert.equal(
    moduleForReleasePath("lib/modules/purchases/pages/detail.dart"),
    "purchases",
  );
  assert.equal(
    moduleForReleasePath("lib/shared/widgets/banner.dart"),
    "general",
  );
  assert.equal(isSensitiveReleasePath(".env.production"), true);
  assert.equal(
    isSensitiveReleasePath("config/credentials/service-account.json"),
    true,
  );
  assert.equal(
    isGeneratedReleasePath("web/spreadsheet_engine/univer.bundle.js"),
    true,
  );
  assert.equal(isGeneratedReleasePath("lib/models/item.g.dart"), true);
  assert.equal(isBinaryReleasePath("assets/photo.png"), true);
});

test("collects an exact multi-commit range with rename and deletion metadata", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });

  assert.equal(inventory.from_commit, fromCommit);
  assert.equal(inventory.to_commit, toCommit);
  assert.equal(inventory.commit_count, 1);
  assert.ok(
    inventory.all_changes.some(
      (entry) =>
        entry.status === "renamed" &&
        entry.previous_path === "lib/modules/bikeshop/pages/job.dart" &&
        entry.path === "lib/modules/bikeshop/pages/quotation.dart",
    ),
  );
  assert.ok(
    inventory.all_changes.some(
      (entry) =>
        entry.status === "deleted" &&
        entry.path === "lib/modules/inventory/old_stock.dart",
    ),
  );

  const aiPaths = new Set(inventory.ai_changes.map((entry) => entry.path));
  assert.ok(aiPaths.has("lib/modules/bikeshop/pages/quotation.dart"));
  assert.ok(aiPaths.has("lib/modules/inventory/old_stock.dart"));
  assert.ok(aiPaths.has("lib/modules/sales/pages/invoice.dart"));
  assert.equal(aiPaths.has(".env.production"), false);
  assert.equal(aiPaths.has("web/spreadsheet_engine/univer.bundle.js"), false);
  assert.equal(aiPaths.has("assets/private-preview.png"), false);
  assert.ok(
    inventory.commits.every(
      (subject) =>
        !subject.includes("sk-this-must-never-reach-the-model") &&
        subject.includes("[dato protegido]"),
    ),
  );
});

test("writes the same bounded es-CL fallback before any optional AI work", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const firstOutput = path.join(repoDir, "out", "first.json");
  const secondOutput = path.join(repoDir, "out", "second.json");
  let fetchCalled = false;

  const first = await generateReleaseNotes({
    repoDir,
    fromCommit,
    toCommit,
    outputPath: firstOutput,
    apiKey: "",
    fetchImpl: async () => {
      fetchCalled = true;
      throw new Error("The network must not be used without a key.");
    },
  });
  const second = await generateReleaseNotes({
    repoDir,
    fromCommit,
    toCommit,
    outputPath: secondOutput,
    apiKey: "",
  });

  assert.equal(fetchCalled, false);
  assert.equal(first.source, "fallback");
  assert.equal(first.reason, "missing_api_key");
  assert.deepEqual(first.release_notes, second.release_notes);
  assert.equal(first.release_notes.schema_version, 1);
  assert.equal(first.release_notes.locale, "es-CL");
  assert.equal(first.release_notes.from_commit, fromCommit);
  assert.equal(first.release_notes.to_commit, toCommit);
  assert.ok(first.release_notes.modules.length >= 1);
  assert.ok(first.release_notes.modules.length <= 5);
  for (const module of first.release_notes.modules) {
    assert.ok(module.items.length >= 1);
    assert.ok(module.items.length <= 3);
    assert.ok(module.items.every((item) => item.length <= 160));
    assert.ok(module.evidence_paths.length >= 1);
    assert.ok(module.evidence_paths.length <= 12);
  }

  const firstJson = await readFile(firstOutput, "utf8");
  const secondJson = await readFile(secondOutput, "utf8");
  assert.equal(firstJson, secondJson);
  assert.deepEqual(JSON.parse(firstJson), {
    release_notes: first.release_notes,
  });
});

test("never exposes protected paths when a range has no safe AI metadata", async (t) => {
  const repoDir = await mkdtemp(
    path.join(os.tmpdir(), "vinabike-protected-release-test-"),
  );
  t.after(async () => {
    await rm(repoDir, { recursive: true, force: true });
  });
  runGit(repoDir, ["init", "--quiet"]);
  runGit(repoDir, ["config", "user.email", "release-tests@vinabike.local"]);
  runGit(repoDir, ["config", "user.name", "Vinabike Release Tests"]);

  await writeRepoFile(repoDir, ".env.production", "TOKEN=old\n");
  await writeRepoFile(repoDir, "config/private.key", "old-private-key\n");
  await writeRepoFile(
    repoDir,
    "web/spreadsheet_engine/univer.bundle.js",
    "old generated bundle\n",
  );
  await writeRepoFile(
    repoDir,
    "assets/preview.png",
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00]),
  );
  const fromCommit = commit(repoDir, "Initial protected files");

  await writeRepoFile(repoDir, ".env.production", "TOKEN=new-secret\n");
  await writeRepoFile(repoDir, "config/private.key", "new-private-key\n");
  await writeRepoFile(
    repoDir,
    "web/spreadsheet_engine/univer.bundle.js",
    "new generated bundle\n",
  );
  await writeRepoFile(
    repoDir,
    "assets/preview.png",
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x01]),
  );
  const toCommit = commit(repoDir, "Refresh protected files");
  const outputPath = path.join(repoDir, "out", "protected.json");

  const result = await generateReleaseNotes({
    repoDir,
    fromCommit,
    toCommit,
    outputPath,
    apiKey: "test-only-key",
    fetchImpl: async () => {
      throw new Error("No AI request is allowed without safe metadata.");
    },
  });

  assert.equal(result.source, "fallback");
  assert.equal(result.reason, "no_safe_ai_metadata");
  assert.equal(result.inventory.ai_changes.length, 0);
  assert.deepEqual(result.release_notes.modules, [
    {
      id: "general",
      label: "General",
      items: [
        "Incluye ajustes internos para mantener la aplicación estable y al día.",
      ],
      evidence_paths: [],
    },
  ]);
  assert.equal(result.release_notes.summary.includes("undefined"), false);
  const saved = await readFile(outputPath, "utf8");
  assert.equal(saved.includes(".env.production"), false);
  assert.equal(saved.includes("private.key"), false);
  assert.equal(saved.includes("univer.bundle.js"), false);
  assert.equal(saved.includes("preview.png"), false);
  assert.equal(saved.includes("new-secret"), false);
});

test("upgrades the fallback only for valid structured AI notes and sends metadata only", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const outputPath = path.join(repoDir, "out", "ai.json");
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });
  const candidate = candidateForInventory(inventory);
  let requestBody;

  const result = await generateReleaseNotes({
    repoDir,
    fromCommit,
    toCommit,
    outputPath,
    apiKey: "test-only-key",
    model: "test-model",
    maxAttempts: 1,
    fetchImpl: async (url, options) => {
      assert.equal(url, "https://api.openai.com/v1/responses");
      assert.equal(options.headers.Authorization, "Bearer test-only-key");
      assert.equal(
        JSON.parse(await readFile(outputPath, "utf8")).release_notes.source,
        "fallback",
      );
      requestBody = JSON.parse(options.body);
      return responseWithCandidate(candidate);
    },
  });

  assert.equal(result.source, "ai");
  assert.equal(result.reason, null);
  assert.equal(result.release_notes.source, "ai");
  validateReleaseNotes(result.release_notes, {
    inventory,
    source: "ai",
  });
  const serializedRequest = JSON.stringify(requestBody);
  assert.equal(serializedRequest.includes(".env.production"), false);
  assert.equal(serializedRequest.includes("super-secret-new-value"), false);
  assert.equal(
    serializedRequest.includes("sk-this-must-never-reach-the-model"),
    false,
  );
  assert.equal(
    serializedRequest.includes("web/spreadsheet_engine/univer.bundle.js"),
    false,
  );
  assert.equal(serializedRequest.includes("assets/private-preview.png"), false);
  assert.equal(requestBody.text.format.type, "json_schema");
  assert.equal(requestBody.text.format.strict, true);
  assert.deepEqual(JSON.parse(await readFile(outputPath, "utf8")), {
    release_notes: result.release_notes,
  });
});

test("keeps the fallback for timeout, 429, malformed JSON, and fabricated evidence", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });
  const validCandidate = candidateForInventory(inventory);
  const fabricatedCandidate = structuredClone(validCandidate);
  fabricatedCandidate.modules[0].evidence_paths = [
    "lib/modules/workshop/never-changed.dart",
  ];

  const cases = [
    {
      name: "timeout",
      fetchImpl: async (_url, options) =>
        new Promise((_resolve, reject) => {
          options.signal.addEventListener(
            "abort",
            () => {
              const error = new Error("timed out");
              error.name = "AbortError";
              reject(error);
            },
            { once: true },
          );
        }),
      timeoutMs: 5,
    },
    {
      name: "rate-limit",
      fetchImpl: async () =>
        new Response("body must not affect fallback", { status: 429 }),
    },
    {
      name: "malformed-api-json",
      fetchImpl: async () =>
        new Response("{", {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
    },
    {
      name: "malformed-model-json",
      fetchImpl: async () =>
        responseWithCandidate({
          ...validCandidate,
          modules: "not-an-array",
        }),
    },
    {
      name: "fabricated-evidence",
      fetchImpl: async () => responseWithCandidate(fabricatedCandidate),
    },
  ];

  for (const scenario of cases) {
    const outputPath = path.join(repoDir, "out", `${scenario.name}.json`);
    const result = await generateReleaseNotes({
      repoDir,
      fromCommit,
      toCommit,
      outputPath,
      apiKey: "test-only-key",
      maxAttempts: 1,
      timeoutMs: scenario.timeoutMs ?? 100,
      fetchImpl: scenario.fetchImpl,
    });

    assert.equal(result.source, "fallback", scenario.name);
    assert.equal(result.release_notes.source, "fallback", scenario.name);
    const saved = JSON.parse(await readFile(outputPath, "utf8"));
    assert.deepEqual(
      saved,
      { release_notes: result.release_notes },
      scenario.name,
    );
  }
});

test("CLI exits zero with fallback and nonzero for an invalid exact commit", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const outputPath = path.join(repoDir, "out", "cli.json");
  const environment = { ...process.env };
  delete environment.OPENAI_API_KEY;
  delete environment.OPENAI_RELEASE_NOTES_ENDPOINT;

  const success = spawnSync(
    process.execPath,
    [
      SCRIPT_PATH,
      "--from-commit",
      fromCommit,
      "--to-commit",
      toCommit,
      "--output",
      outputPath,
    ],
    {
      cwd: repoDir,
      env: environment,
      encoding: "utf8",
    },
  );
  assert.equal(success.status, 0, success.stderr);
  assert.match(success.stdout, /Release notes source: fallback/u);
  assert.equal(
    JSON.parse(await readFile(outputPath, "utf8")).release_notes.source,
    "fallback",
  );

  const failure = spawnSync(
    process.execPath,
    [
      SCRIPT_PATH,
      "--from-commit",
      "0".repeat(40),
      "--to-commit",
      toCommit,
      "--output",
      path.join(repoDir, "out", "invalid.json"),
    ],
    {
      cwd: repoDir,
      env: environment,
      encoding: "utf8",
    },
  );
  assert.notEqual(failure.status, 0);
  assert.match(failure.stderr, /from-commit is not an available Git commit/u);
});

test("fallback validation rejects evidence outside the exact changed paths", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });
  const fallback = createFallbackReleaseNotes(inventory);
  fallback.modules[0].evidence_paths = ["lib/not-in-the-range.dart"];

  assert.throws(
    () =>
      validateReleaseNotes(fallback, {
        inventory,
        source: "fallback",
      }),
    /unsupported evidence/u,
  );
});
