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

async function createPrivacyFixtureRepo(t) {
  const repoDir = await mkdtemp(
    path.join(os.tmpdir(), "vinabike-private-release-notes-test-"),
  );
  t.after(async () => {
    await rm(repoDir, { recursive: true, force: true });
  });

  runGit(repoDir, ["init", "--quiet"]);
  runGit(repoDir, ["config", "user.email", "release-tests@vinabike.local"]);
  runGit(repoDir, ["config", "user.name", "Vinabike Release Tests"]);

  const previousPath =
    "lib/modules/sales/customers/customer_ana.soto@example.cl_phone_+56-9-8765-4321_rut_12.345.678-5_invoice_FAC-77881.dart";
  const currentPath =
    "lib/modules/sales/customers/customer_pedro.rios@example.cl_phone_+56-9-1234-5678_rut_9.876.543-2_order_ORD-99110.dart";
  await writeRepoFile(
    repoDir,
    previousPath,
    'const privateCustomerRecord = "ana.soto@example.cl +56 9 8765 4321 12.345.678-5 FAC-77881";\n',
  );
  const fromCommit = commit(repoDir, "Initial private customer record");

  await rename(
    path.join(repoDir, previousPath),
    path.join(repoDir, currentPath),
  );
  const privateCommitSubject =
    "Fix customer Pedro Rios pedro.rios@example.cl +56 9 1234 5678 RUT 9.876.543-2 order ORD-99110";
  const toCommit = commit(repoDir, privateCommitSubject);

  return {
    repoDir,
    fromCommit,
    toCommit,
    previousPath,
    currentPath,
    privateCommitSubject,
    privateValues: [
      "ana.soto@example.cl",
      "pedro.rios@example.cl",
      "+56-9-8765-4321",
      "+56-9-1234-5678",
      "12.345.678-5",
      "9.876.543-2",
      "FAC-77881",
      "ORD-99110",
    ],
  };
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

function geminiResponseWithCandidate(candidate) {
  const serializedCandidate = JSON.stringify(candidate);
  const splitAt = Math.ceil(serializedCandidate.length / 2);
  return new Response(
    JSON.stringify({
      candidates: [
        {
          content: {
            role: "model",
            parts: [
              { thought: true, text: "Internal reasoning is not output JSON." },
              { text: serializedCandidate.slice(0, splitAt) },
              { text: serializedCandidate.slice(splitAt) },
            ],
          },
          finishReason: "STOP",
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
  for (const [index, entry] of inventory.ai_changes.entries()) {
    if (!evidenceByModule.has(entry.module_id)) {
      evidenceByModule.set(
        entry.module_id,
        `change_${String(index + 1).padStart(3, "0")}`,
      );
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
    modules: [...evidenceByModule.entries()].map(([moduleId, evidenceId]) => ({
      id: moduleId,
      label: labels[moduleId],
      items: [copy[moduleId]],
      evidence_ids: [evidenceId],
    })),
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

test("upgrades the fallback only for valid structured OpenAI notes and sends metadata only", async (t) => {
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
  assert.equal(
    requestBody.text.format.schema.properties.modules.items.properties
      .evidence_ids.uniqueItems,
    undefined,
  );
  assert.equal(
    Object.hasOwn(
      requestBody.text.format.schema.properties.modules.items.properties,
      "evidence_paths",
    ),
    false,
  );
  assert.deepEqual(JSON.parse(await readFile(outputPath, "utf8")), {
    release_notes: result.release_notes,
  });
});

test("prefers Gemini, sends only bounded metadata, and accepts validated structured notes", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const outputPath = path.join(repoDir, "out", "gemini-ai.json");
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });
  const candidate = candidateForInventory(inventory);
  const geminiSecret = "gemini-test-secret-that-must-not-leak";
  const openAiSecret = "openai-test-secret-that-must-not-leak";
  let requestBody;
  let requestCount = 0;

  const result = await generateReleaseNotes({
    repoDir,
    fromCommit,
    toCommit,
    outputPath,
    geminiApiKey: geminiSecret,
    apiKey: openAiSecret,
    maxAttempts: 1,
    fetchImpl: async (url, options) => {
      requestCount += 1;
      assert.equal(
        url,
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent",
      );
      assert.equal(options.headers["x-goog-api-key"], geminiSecret);
      assert.equal(Object.hasOwn(options.headers, "Authorization"), false);
      assert.equal(
        JSON.parse(await readFile(outputPath, "utf8")).release_notes.source,
        "fallback",
      );
      requestBody = JSON.parse(options.body);
      return geminiResponseWithCandidate(candidate);
    },
  });

  assert.equal(requestCount, 1);
  assert.equal(result.source, "ai");
  assert.equal(result.reason, null);
  assert.equal(result.provider, "gemini");
  assert.equal(result.model, "gemini-3.1-flash-lite");
  validateReleaseNotes(result.release_notes, {
    inventory,
    source: "ai",
  });

  assert.deepEqual(Object.keys(requestBody).sort(), [
    "contents",
    "generationConfig",
    "systemInstruction",
  ]);
  assert.equal(requestBody.contents.length, 1);
  assert.equal(requestBody.contents[0].role, "user");
  assert.equal(requestBody.contents[0].parts.length, 1);
  const metadata = JSON.parse(requestBody.contents[0].parts[0].text);
  assert.deepEqual(Object.keys(metadata).sort(), [
    "change_count",
    "changes",
    "commit_count",
    "included_change_count",
    "locale",
    "module_labels",
    "omitted_or_protected_change_count",
    "topic_labels",
  ]);
  assert.deepEqual(
    metadata.changes,
    inventory.ai_changes.map((entry, index) => ({
      evidence_id: `change_${String(index + 1).padStart(3, "0")}`,
      module_id: entry.module_id,
      topic_id:
        entry.module_id === "general"
          ? "general_experience"
          : {
              workshop: "workshop_operations",
              inventory: "inventory_operations",
              sales: "sales_operations",
            }[entry.module_id],
      status: entry.status,
      additions: entry.additions,
      deletions: entry.deletions,
    })),
  );
  assert.equal(metadata.change_count, inventory.all_changes.length);
  assert.equal(metadata.included_change_count, inventory.ai_changes.length);
  assert.equal(metadata.changes.length <= 240, true);
  assert.equal(
    requestBody.generationConfig.responseMimeType,
    "application/json",
  );
  assert.equal(requestBody.generationConfig.responseJsonSchema.type, "object");
  assert.equal(
    requestBody.generationConfig.responseJsonSchema.additionalProperties,
    false,
  );
  assert.equal(
    requestBody.generationConfig.responseJsonSchema.properties.title.maxLength,
    undefined,
  );
  assert.equal(
    Object.hasOwn(
      requestBody.generationConfig.responseJsonSchema.properties.modules.items
        .properties,
      "evidence_paths",
    ),
    false,
  );
  assert.equal(
    Object.hasOwn(requestBody.generationConfig, "responseFormat"),
    false,
  );

  const serializedRequest = JSON.stringify(requestBody);
  for (const protectedValue of [
    geminiSecret,
    openAiSecret,
    ".env.production",
    "super-secret-new-value",
    "sk-this-must-never-reach-the-model",
    "web/spreadsheet_engine/univer.bundle.js",
    "assets/private-preview.png",
    "class InvoicePage",
  ]) {
    assert.equal(serializedRequest.includes(protectedValue), false);
  }
  for (const entry of inventory.all_changes) {
    assert.equal(serializedRequest.includes(entry.path), false);
    if (entry.previous_path) {
      assert.equal(serializedRequest.includes(entry.previous_path), false);
    }
  }
  assert.equal(serializedRequest.includes(fromCommit), false);
  assert.equal(serializedRequest.includes(toCommit), false);
  for (const subject of inventory.commits) {
    assert.equal(serializedRequest.includes(subject), false);
  }

  for (const module of result.release_notes.modules) {
    const providerModule = candidate.modules.find(
      (candidateModule) => candidateModule.id === module.id,
    );
    const expectedPaths = providerModule.evidence_ids.map((evidenceId) => {
      const index = Number.parseInt(evidenceId.slice("change_".length), 10) - 1;
      return inventory.ai_changes[index].path;
    });
    assert.deepEqual(module.evidence_paths, expectedPaths);
  }
  assert.deepEqual(JSON.parse(await readFile(outputPath, "utf8")), {
    release_notes: result.release_notes,
  });
});

test("recovers from a Gemini model 404 through allowlisted model discovery", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const outputPath = path.join(repoDir, "out", "gemini-model-recovery.json");
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });
  const candidate = candidateForInventory(inventory);
  const geminiSecret = "gemini-model-recovery-secret";
  const requests = [];

  const result = await generateReleaseNotes({
    repoDir,
    fromCommit,
    toCommit,
    outputPath,
    geminiApiKey: geminiSecret,
    geminiModel: "gemini-unavailable-model",
    maxAttempts: 2,
    fetchImpl: async (url, options) => {
      requests.push({
        url,
        method: options.method,
        headers: options.headers,
        body: options.body,
      });

      if (
        url ===
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-unavailable-model:generateContent"
      ) {
        assert.equal(options.method, "POST");
        return new Response(
          JSON.stringify({
            error: {
              code: 404,
              status: "NOT_FOUND",
              message: "Configured model is not available.",
            },
          }),
          { status: 404 },
        );
      }
      if (
        url ===
        "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000"
      ) {
        assert.equal(options.method, "GET");
        assert.equal(options.headers["x-goog-api-key"], geminiSecret);
        assert.equal(Object.hasOwn(options, "body"), false);
        return new Response(
          JSON.stringify({
            models: [
              {
                name: "models/gemini-untrusted-model",
                baseModelId: "gemini-untrusted-model",
                supportedGenerationMethods: ["generateContent"],
              },
              {
                name: "models/gemini-3.1-flash-lite",
                baseModelId: "gemini-3.1-flash-lite",
                supportedGenerationMethods: ["generateContent"],
              },
              {
                name: "models/gemini-3.5-flash-lite",
                baseModelId: "gemini-3.5-flash-lite",
                supportedGenerationMethods: ["generateContent"],
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (
        url ===
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent"
      ) {
        assert.equal(options.method, "POST");
        const body = JSON.parse(options.body);
        assert.equal(body.generationConfig.maxOutputTokens, 1_200);
        assert.equal(
          body.generationConfig.responseMimeType,
          "application/json",
        );
        assert.equal(body.generationConfig.responseJsonSchema.type, "object");
        assert.equal(
          Object.hasOwn(body.generationConfig, "responseFormat"),
          false,
        );
        const serializedBody = JSON.stringify(body);
        assert.equal(serializedBody.includes(fromCommit), false);
        assert.equal(serializedBody.includes(toCommit), false);
        for (const entry of inventory.all_changes) {
          assert.equal(serializedBody.includes(entry.path), false);
          if (entry.previous_path) {
            assert.equal(serializedBody.includes(entry.previous_path), false);
          }
        }
        return geminiResponseWithCandidate(candidate);
      }
      throw new Error(`Unexpected Gemini test URL: ${url}`);
    },
  });

  assert.equal(result.source, "ai");
  assert.equal(result.reason, null);
  assert.equal(result.provider, "gemini");
  assert.equal(result.model, "gemini-3.1-flash-lite");
  assert.deepEqual(
    requests.map((request) => [request.method, request.url]),
    [
      [
        "POST",
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-unavailable-model:generateContent",
      ],
      [
        "GET",
        "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000",
      ],
      [
        "POST",
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent",
      ],
    ],
  );
  assert.ok(
    requests.every(
      (request) =>
        !request.url.includes(geminiSecret) &&
        request.headers["x-goog-api-key"] === geminiSecret,
    ),
  );
  assert.deepEqual(JSON.parse(await readFile(outputPath, "utf8")), {
    release_notes: result.release_notes,
  });
});

test("recovers from Gemini 400 INVALID_ARGUMENT through allowlisted model discovery", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const outputPath = path.join(
    repoDir,
    "out",
    "gemini-invalid-argument-recovery.json",
  );
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });
  const candidate = candidateForInventory(inventory);
  const geminiSecret = "gemini-invalid-argument-recovery-secret";
  const privateGoogleError =
    "customer@example.com /private/customer/invoice-123 secret-key";
  const requests = [];

  const result = await generateReleaseNotes({
    repoDir,
    fromCommit,
    toCommit,
    outputPath,
    geminiApiKey: geminiSecret,
    geminiModel: "gemini-2.5-flash-lite",
    maxAttempts: 2,
    fetchImpl: async (url, options) => {
      requests.push({
        url,
        method: options.method,
        headers: options.headers,
        body: options.body,
      });

      if (
        url ===
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
      ) {
        const body = JSON.parse(options.body);
        assert.equal(
          body.generationConfig.responseMimeType,
          "application/json",
        );
        assert.equal(body.generationConfig.responseJsonSchema.type, "object");
        assert.equal(
          Object.hasOwn(body.generationConfig, "responseFormat"),
          false,
        );
        return new Response(
          JSON.stringify({
            error: {
              code: 400,
              status: "INVALID_ARGUMENT",
              message: privateGoogleError,
            },
          }),
          { status: 400 },
        );
      }
      if (
        url ===
        "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000"
      ) {
        assert.equal(options.method, "GET");
        assert.equal(Object.hasOwn(options, "body"), false);
        return new Response(
          JSON.stringify({
            models: [
              {
                name: "models/gemini-untrusted-model",
                supportedGenerationMethods: ["generateContent"],
              },
              {
                name: "models/gemini-3.1-flash-lite",
                supportedGenerationMethods: ["generateContent"],
              },
              {
                name: "models/gemini-2.5-flash-lite",
                supportedGenerationMethods: ["generateContent"],
              },
            ],
          }),
          { status: 200 },
        );
      }
      if (
        url ===
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent"
      ) {
        const body = JSON.parse(options.body);
        assert.equal(
          body.generationConfig.responseMimeType,
          "application/json",
        );
        assert.equal(body.generationConfig.responseJsonSchema.type, "object");
        assert.equal(
          Object.hasOwn(body.generationConfig, "responseFormat"),
          false,
        );
        return geminiResponseWithCandidate(candidate);
      }
      throw new Error(`Unexpected Gemini test URL: ${url}`);
    },
  });

  assert.equal(result.source, "ai");
  assert.equal(result.reason, null);
  assert.equal(result.provider, "gemini");
  assert.equal(result.model, "gemini-3.1-flash-lite");
  assert.deepEqual(
    requests.map((request) => [request.method, request.url]),
    [
      [
        "POST",
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent",
      ],
      [
        "GET",
        "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000",
      ],
      [
        "POST",
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent",
      ],
    ],
  );
  assert.ok(
    requests.every(
      (request) =>
        !request.url.includes(geminiSecret) &&
        request.headers["x-goog-api-key"] === geminiSecret,
    ),
  );
  const discoveryRequest = requests[1];
  assert.equal(discoveryRequest.body, undefined);
  const saved = await readFile(outputPath, "utf8");
  assert.equal(saved.includes(privateGoogleError), false);
  assert.equal(saved.includes(geminiSecret), false);
});

test("does not select arbitrary or incompatible models discovered after a Gemini 404", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const outputPath = path.join(repoDir, "out", "gemini-no-safe-model.json");
  const requestedUrls = [];
  const privateGoogleError =
    "customer@example.com /private/customer/invoice-123 secret-key";

  const result = await generateReleaseNotes({
    repoDir,
    fromCommit,
    toCommit,
    outputPath,
    geminiApiKey: "test-only-gemini-key",
    geminiModel: "gemini-unavailable-model",
    maxAttempts: 2,
    fetchImpl: async (url) => {
      requestedUrls.push(url);
      if (url.endsWith(":generateContent")) {
        return new Response(
          JSON.stringify({
            error: {
              code: 404,
              status: "NOT_FOUND",
              message: privateGoogleError,
            },
          }),
          { status: 404 },
        );
      }
      return new Response(
        JSON.stringify({
          models: [
            {
              name: "models/gemini-untrusted-model",
              baseModelId: "gemini-untrusted-model",
              supportedGenerationMethods: ["generateContent"],
            },
            {
              name: "models/gemini-3.5-flash-lite",
              baseModelId: "gemini-3.5-flash-lite",
              supportedGenerationMethods: ["embedContent"],
            },
          ],
        }),
        { status: 200 },
      );
    },
  });

  assert.equal(result.source, "fallback");
  assert.equal(result.reason, "http_404_not_found");
  assert.equal(result.provider, "gemini");
  assert.equal(result.model, "gemini-unavailable-model");
  assert.equal(result.reason.includes(privateGoogleError), false);
  assert.deepEqual(requestedUrls, [
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-unavailable-model:generateContent",
    "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000",
  ]);
  const saved = await readFile(outputPath, "utf8");
  assert.equal(JSON.parse(saved).release_notes.source, "fallback");
  assert.equal(saved.includes(privateGoogleError), false);
});

test("both AI providers receive only opaque allowlisted metadata even when Git contains private identifiers", async (t) => {
  const {
    repoDir,
    fromCommit,
    toCommit,
    previousPath,
    currentPath,
    privateCommitSubject,
    privateValues,
  } = await createPrivacyFixtureRepo(t);
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });
  assert.equal(inventory.ai_changes.length, 1);
  assert.equal(inventory.ai_changes[0].status, "renamed");
  assert.equal(inventory.ai_changes[0].previous_path, previousPath);
  assert.equal(inventory.ai_changes[0].path, currentPath);
  const candidate = candidateForInventory(inventory);

  const providers = [
    {
      name: "openai",
      args: { apiKey: "private-openai-test-key" },
      respond: () => responseWithCandidate(candidate),
      metadataFromBody: (body) => JSON.parse(body.input[1].content[0].text),
    },
    {
      name: "gemini",
      args: { geminiApiKey: "private-gemini-test-key" },
      respond: () => geminiResponseWithCandidate(candidate),
      metadataFromBody: (body) => JSON.parse(body.contents[0].parts[0].text),
    },
  ];

  for (const provider of providers) {
    const outputPath = path.join(
      repoDir,
      "out",
      `private-${provider.name}.json`,
    );
    let requestBody;
    const result = await generateReleaseNotes({
      repoDir,
      fromCommit,
      toCommit,
      outputPath,
      maxAttempts: 1,
      ...provider.args,
      fetchImpl: async (_url, options) => {
        requestBody = JSON.parse(options.body);
        return provider.respond();
      },
    });

    assert.equal(result.source, "ai", provider.name);
    const metadata = provider.metadataFromBody(requestBody);
    assert.deepEqual(Object.keys(metadata).sort(), [
      "change_count",
      "changes",
      "commit_count",
      "included_change_count",
      "locale",
      "module_labels",
      "omitted_or_protected_change_count",
      "topic_labels",
    ]);
    assert.deepEqual(metadata.changes, [
      {
        evidence_id: "change_001",
        module_id: "sales",
        topic_id: "sales_operations",
        status: "renamed",
        additions: inventory.ai_changes[0].additions,
        deletions: inventory.ai_changes[0].deletions,
      },
    ]);
    assert.deepEqual(
      Object.keys(metadata.changes[0]).sort(),
      [
        "additions",
        "deletions",
        "evidence_id",
        "module_id",
        "status",
        "topic_id",
      ],
      provider.name,
    );

    const serializedRequest = JSON.stringify(requestBody);
    for (const forbiddenValue of [
      fromCommit,
      toCommit,
      previousPath,
      currentPath,
      privateCommitSubject,
      ...inventory.commits,
      ...privateValues,
      "privateCustomerRecord",
      "from_commit",
      "to_commit",
      "commit_subjects",
      "changed_paths",
      "previous_path",
      "evidence_paths",
    ]) {
      assert.equal(
        serializedRequest.includes(forbiddenValue),
        false,
        `${provider.name}: ${forbiddenValue}`,
      );
    }
    assert.deepEqual(result.release_notes.modules[0].evidence_paths, [
      currentPath,
    ]);
  }
});

test("Gemini failures keep the fallback without OpenAI failover or secret leakage", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const geminiSecret = "gemini-network-secret-that-must-not-leak";
  const openAiSecret = "openai-failover-secret-that-must-not-leak";
  const cases = [
    {
      name: "service-unavailable",
      fetchImpl: async () =>
        new Response(`provider error ${geminiSecret}`, { status: 503 }),
      expectedReason: "http_503",
    },
    {
      name: "network-error",
      fetchImpl: async () => {
        throw new Error(`network failure ${geminiSecret}`);
      },
      expectedReason: "network_error",
    },
  ];

  for (const scenario of cases) {
    const outputPath = path.join(
      repoDir,
      "out",
      `gemini-${scenario.name}.json`,
    );
    const requestedUrls = [];
    const result = await generateReleaseNotes({
      repoDir,
      fromCommit,
      toCommit,
      outputPath,
      geminiApiKey: geminiSecret,
      apiKey: openAiSecret,
      maxAttempts: 1,
      fetchImpl: async (url, options) => {
        requestedUrls.push(url);
        assert.equal(options.headers["x-goog-api-key"], geminiSecret);
        assert.equal(Object.hasOwn(options.headers, "Authorization"), false);
        return scenario.fetchImpl(url, options);
      },
    });

    assert.deepEqual(requestedUrls, [
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent",
    ]);
    assert.equal(result.source, "fallback", scenario.name);
    assert.equal(result.reason, scenario.expectedReason, scenario.name);
    const saved = await readFile(outputPath, "utf8");
    assert.equal(saved.includes(geminiSecret), false, scenario.name);
    assert.equal(saved.includes(openAiSecret), false, scenario.name);
    assert.equal(
      JSON.stringify(result).includes(geminiSecret),
      false,
      scenario.name,
    );
    assert.equal(
      JSON.stringify(result).includes(openAiSecret),
      false,
      scenario.name,
    );
  }
});

test("Gemini output still passes the exact evidence validator before replacing fallback", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const outputPath = path.join(repoDir, "out", "gemini-invalid.json");
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });
  const fabricatedCandidate = candidateForInventory(inventory);
  fabricatedCandidate.modules[0].evidence_ids = ["change_999"];

  const result = await generateReleaseNotes({
    repoDir,
    fromCommit,
    toCommit,
    outputPath,
    geminiApiKey: "test-only-gemini-key",
    maxAttempts: 1,
    fetchImpl: async () => geminiResponseWithCandidate(fabricatedCandidate),
  });

  assert.equal(result.source, "fallback");
  assert.equal(result.reason, "invalid_ai_release_notes");
  assert.equal(
    JSON.parse(await readFile(outputPath, "utf8")).release_notes.source,
    "fallback",
  );
});

test("hallucinated private identifiers in AI text never replace the safe fallback", async (t) => {
  const { repoDir, fromCommit, toCommit } = await createFixtureRepo(t);
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });
  const privateTextCases = [
    "Escriba a persona@example.cl para conocer el cambio.",
    "Se revisó el registro asociado al RUT 12.345.678-5.",
    "Se mejoró el contacto al +56 9 1234 5678.",
    "Se ajustó el cliente CLI-77881.",
    "Se ajustó la factura FAC-77881.",
    "Se ajustó la orden ORD-99110.",
  ];

  for (const [index, privateText] of privateTextCases.entries()) {
    const candidate = candidateForInventory(inventory);
    candidate.modules[0].items = [privateText];
    const outputPath = path.join(
      repoDir,
      "out",
      `private-ai-text-${index}.json`,
    );
    const result = await generateReleaseNotes({
      repoDir,
      fromCommit,
      toCommit,
      outputPath,
      apiKey: "test-only-key",
      maxAttempts: 1,
      fetchImpl: async () => responseWithCandidate(candidate),
    });

    assert.equal(result.source, "fallback", privateText);
    assert.equal(result.reason, "invalid_ai_release_notes", privateText);
    const saved = await readFile(outputPath, "utf8");
    assert.equal(saved.includes(privateText), false, privateText);
  }
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
  fabricatedCandidate.modules[0].evidence_ids = ["change_999"];

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
  delete environment.GEMINI_RELEASE_API_KEY;
  delete environment.GEMINI_RELEASE_NOTES_MODEL;
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
