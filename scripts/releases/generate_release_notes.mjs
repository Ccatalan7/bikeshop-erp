#!/usr/bin/env node

import { execFileSync, spawnSync } from "node:child_process";
import { mkdir, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const COMMIT_PATTERN = /^[0-9a-f]{40}$/u;
const DEFAULT_MODEL = "gpt-5-mini";
const DEFAULT_ENDPOINT = "https://api.openai.com/v1/responses";
const DEFAULT_GEMINI_MODEL = "gemini-3.1-flash-lite";
const GEMINI_MODEL_PATTERN = /^[a-z0-9][a-z0-9._-]{0,79}$/u;
const GEMINI_ENDPOINT_ROOT =
  "https://generativelanguage.googleapis.com/v1beta/models";
const GEMINI_MODELS_ENDPOINT = `${GEMINI_ENDPOINT_ROOT}?pageSize=1000`;
const GEMINI_FALLBACK_MODELS = Object.freeze([
  "gemini-3.1-flash-lite",
  "gemini-3.5-flash-lite",
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite",
]);
const SAFE_API_ERROR_CATEGORIES = new Map([
  ["ABORTED", "aborted"],
  ["DEADLINE_EXCEEDED", "deadline_exceeded"],
  ["FAILED_PRECONDITION", "failed_precondition"],
  ["INTERNAL", "internal"],
  ["INVALID_ARGUMENT", "invalid_argument"],
  ["NOT_FOUND", "not_found"],
  ["PERMISSION_DENIED", "permission_denied"],
  ["RESOURCE_EXHAUSTED", "resource_exhausted"],
  ["UNAUTHENTICATED", "unauthenticated"],
  ["UNAVAILABLE", "unavailable"],
]);
const DEFAULT_TIMEOUT_MS = 12_000;
const DEFAULT_MAX_ATTEMPTS = 2;
const MAX_API_RESPONSE_BYTES = 256 * 1024;
const MAX_MODEL_OUTPUT_CHARS = 32 * 1024;
const MAX_PROMPT_CHANGES = 240;
const MAX_PROMPT_COMMITS = 40;

export const RELEASE_NOTE_MODULES = Object.freeze({
  workshop: "Taller",
  inventory: "Inventario",
  sales: "Ventas y pagos",
  purchases: "Compras",
  hr: "Personal",
  messaging: "Mensajes",
  mail: "Correo",
  website: "Sitio web",
  storage: "Archivos",
  accounting: "Contabilidad",
  settings: "Configuración",
  general: "General",
});

const MODULE_ORDER = Object.freeze(Object.keys(RELEASE_NOTE_MODULES));
const MODULE_ORDER_INDEX = new Map(
  MODULE_ORDER.map((moduleId, index) => [moduleId, index]),
);

const RELEASE_NOTE_TOPICS = Object.freeze({
  workshop_operations: "Trabajos y presupuestos",
  inventory_operations: "Productos y existencias",
  sales_operations: "Ventas, cobros y clientes",
  purchase_operations: "Compras y proveedores",
  hr_operations: "Personal y turnos",
  messaging_operations: "Mensajes y conversaciones",
  mail_operations: "Correo",
  website_operations: "Catálogo y navegación del sitio web",
  storage_operations: "Archivos y documentos",
  accounting_operations: "Gastos y contabilidad",
  settings_operations: "Configuración y acceso",
  desktop_updates: "Actualizaciones de la aplicación",
  notifications: "Notificaciones",
  general_experience: "Experiencia general",
});

const DEFAULT_TOPIC_BY_MODULE = Object.freeze({
  workshop: "workshop_operations",
  inventory: "inventory_operations",
  sales: "sales_operations",
  purchases: "purchase_operations",
  hr: "hr_operations",
  messaging: "messaging_operations",
  mail: "mail_operations",
  website: "website_operations",
  storage: "storage_operations",
  accounting: "accounting_operations",
  settings: "settings_operations",
  general: "general_experience",
});

const FALLBACK_ITEMS = Object.freeze({
  workshop:
    "Incluye ajustes y mejoras de estabilidad en las herramientas de Taller.",
  inventory:
    "Incluye ajustes y mejoras de estabilidad en la gestión de Inventario.",
  sales: "Incluye ajustes y mejoras de estabilidad en Ventas y pagos.",
  purchases:
    "Incluye ajustes y mejoras de estabilidad en la gestión de Compras.",
  hr: "Incluye ajustes y mejoras de estabilidad en las herramientas de Personal.",
  messaging:
    "Incluye ajustes y mejoras de estabilidad en las herramientas de Mensajes.",
  mail: "Incluye ajustes y mejoras de estabilidad en las herramientas de Correo.",
  website:
    "Incluye ajustes y mejoras de estabilidad en la gestión del Sitio web.",
  storage:
    "Incluye ajustes y mejoras de estabilidad en la gestión de Archivos.",
  accounting:
    "Incluye ajustes y mejoras de estabilidad en las herramientas de Contabilidad.",
  settings:
    "Incluye ajustes y mejoras de estabilidad en la Configuración de la aplicación.",
  general:
    "Incluye ajustes internos para mantener la aplicación estable y al día.",
});

const BINARY_EXTENSIONS = new Set([
  ".7z",
  ".a",
  ".app",
  ".avi",
  ".bin",
  ".bmp",
  ".db",
  ".dmg",
  ".dll",
  ".dylib",
  ".eot",
  ".exe",
  ".gif",
  ".gz",
  ".heic",
  ".ico",
  ".jar",
  ".jpeg",
  ".jpg",
  ".mov",
  ".mp3",
  ".mp4",
  ".o",
  ".otf",
  ".pdf",
  ".pkl",
  ".png",
  ".so",
  ".sqlite",
  ".tar",
  ".tiff",
  ".ttf",
  ".wav",
  ".webm",
  ".webp",
  ".woff",
  ".woff2",
  ".xcarchive",
  ".zip",
]);

const SENSITIVE_EXTENSIONS = new Set([
  ".der",
  ".jks",
  ".key",
  ".keystore",
  ".p12",
  ".pfx",
  ".pem",
]);

const GENERATED_FILE_NAMES = new Set([
  "package-lock.json",
  "podfile.lock",
  "pubspec.lock",
]);

function git(repoDir, args, { encoding = "utf8" } = {}) {
  try {
    return execFileSync("git", args, {
      cwd: repoDir,
      encoding,
      maxBuffer: 16 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch {
    throw new Error(`Git metadata command failed: git ${args[0] ?? ""}.`);
  }
}

function isAncestor(repoDir, fromCommit, toCommit) {
  const result = spawnSync(
    "git",
    ["merge-base", "--is-ancestor", fromCommit, toCommit],
    {
      cwd: repoDir,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  if (result.status === 0) return true;
  if (result.status === 1) return false;
  throw new Error("Git could not validate the release commit range.");
}

function assertCommit(repoDir, value, label) {
  const normalized = String(value ?? "")
    .trim()
    .toLowerCase();
  if (!COMMIT_PATTERN.test(normalized)) {
    throw new Error(`${label} must be a full 40-character Git commit.`);
  }

  try {
    git(repoDir, ["cat-file", "-e", `${normalized}^{commit}`]);
  } catch {
    throw new Error(`${label} is not an available Git commit.`);
  }
  return normalized;
}

function parseNameStatus(buffer) {
  const tokens = buffer.toString("utf8").split("\0");
  if (tokens.at(-1) === "") tokens.pop();

  const entries = [];
  for (let index = 0; index < tokens.length;) {
    const statusCode = tokens[index++];
    if (!statusCode) continue;

    if (statusCode.startsWith("R") || statusCode.startsWith("C")) {
      const previousPath = tokens[index++];
      const currentPath = tokens[index++];
      if (!previousPath || !currentPath) {
        throw new Error("Git returned incomplete rename metadata.");
      }
      entries.push({
        status: statusCode.startsWith("R") ? "renamed" : "copied",
        status_code: statusCode,
        previous_path: previousPath,
        path: currentPath,
      });
      continue;
    }

    const currentPath = tokens[index++];
    if (!currentPath) {
      throw new Error("Git returned incomplete changed-path metadata.");
    }
    const status = {
      A: "added",
      D: "deleted",
      M: "modified",
      T: "type_changed",
      U: "unmerged",
    }[statusCode[0]];
    entries.push({
      status: status ?? "modified",
      status_code: statusCode,
      path: currentPath,
    });
  }
  return entries;
}

function parseNumstat(buffer) {
  const stats = new Map();
  for (const record of buffer.toString("utf8").split("\0")) {
    if (!record) continue;
    const firstTab = record.indexOf("\t");
    const secondTab = record.indexOf("\t", firstTab + 1);
    if (firstTab < 0 || secondTab < 0) continue;

    const additionsText = record.slice(0, firstTab);
    const deletionsText = record.slice(firstTab + 1, secondTab);
    const filePath = record.slice(secondTab + 1);
    if (!filePath) continue;
    const binary = additionsText === "-" || deletionsText === "-";
    stats.set(filePath, {
      additions: binary ? null : Number.parseInt(additionsText, 10),
      deletions: binary ? null : Number.parseInt(deletionsText, 10),
      binary,
    });
  }
  return stats;
}

function sanitizeCommitSubject(subject) {
  return subject
    .replace(/[\u0000-\u001f\u007f]+/gu, " ")
    .replace(/https?:\/\/\S+/giu, "[enlace omitido]")
    .replace(
      /\b(?:sk|ghp|github_pat|xox[baprs])-?[A-Za-z0-9_-]{12,}\b/gu,
      "[dato protegido]",
    )
    .replace(
      /\b(?:token|secret|password|passwd|api[_ -]?key)\s*[:=]\s*\S+/giu,
      "[dato protegido]",
    )
    .replace(/\b[A-Za-z0-9_+/=-]{40,}\b/gu, "[dato protegido]")
    .replace(/\s+/gu, " ")
    .trim()
    .slice(0, 180);
}

function parseCommitSubjects(repoDir, fromCommit, toCommit) {
  const output = git(repoDir, [
    "log",
    "--reverse",
    "--format=%s",
    "-z",
    `${fromCommit}..${toCommit}`,
  ]);
  return output
    .split("\0")
    .map(sanitizeCommitSubject)
    .filter(Boolean)
    .slice(0, MAX_PROMPT_COMMITS);
}

function pathParts(filePath) {
  return filePath.toLowerCase().split("/");
}

export function isSensitiveReleasePath(filePath) {
  const lowerPath = filePath.toLowerCase();
  const parts = pathParts(filePath);
  const basename = parts.at(-1) ?? "";
  const extension = path.posix.extname(lowerPath);

  if (
    basename === ".env" ||
    basename.startsWith(".env.") ||
    basename === ".envrc" ||
    basename === ".npmrc" ||
    basename === ".pypirc" ||
    basename === "id_rsa" ||
    basename === "id_ed25519" ||
    basename === "google-services.json" ||
    basename === "googleservice-info.plist" ||
    /^(?:client[_-]?secret|credentials?|service[_-]?account|secrets?)(?:[._-]|$)/u.test(
      basename,
    ) ||
    SENSITIVE_EXTENSIONS.has(extension)
  ) {
    return true;
  }

  return parts.some((part) =>
    /^(?:credentials?|private[_-]?keys?|secrets?)$/u.test(part),
  );
}

export function isGeneratedReleasePath(filePath) {
  const lowerPath = filePath.toLowerCase();
  const parts = pathParts(filePath);
  const basename = parts.at(-1) ?? "";

  if (GENERATED_FILE_NAMES.has(basename)) return true;
  if (/^(?:generated[_-]|.*\.generated\.)/u.test(basename)) return true;
  if (
    parts.some((part) =>
      [
        ".dart_tool",
        ".firebase",
        ".gradle",
        ".idea",
        ".pub-cache",
        ".swiftpm",
        "build",
        "deriveddata",
        "dist",
        "ephemeral",
        "node_modules",
        "pods",
      ].includes(part),
    )
  ) {
    return true;
  }

  return (
    lowerPath.endsWith(".g.dart") ||
    lowerPath.endsWith(".freezed.dart") ||
    lowerPath.endsWith(".mocks.dart") ||
    lowerPath.endsWith(".bundle.js") ||
    lowerPath.endsWith(".min.js") ||
    lowerPath.endsWith(".map")
  );
}

export function isBinaryReleasePath(filePath) {
  return BINARY_EXTENSIONS.has(path.posix.extname(filePath.toLowerCase()));
}

function isSafeRepoRelativePath(filePath) {
  if (
    typeof filePath !== "string" ||
    filePath.length < 1 ||
    filePath.length > 500 ||
    filePath.includes("\\") ||
    filePath.includes("\0") ||
    path.posix.isAbsolute(filePath)
  ) {
    return false;
  }
  const parts = filePath.split("/");
  return !parts.some((part) => !part || part === "." || part === "..");
}

export function moduleForReleasePath(filePath) {
  const value = filePath.toLowerCase();
  const matches = (...patterns) =>
    patterns.some((pattern) => pattern.test(value));

  if (
    matches(
      /(?:^|\/)(?:workshop|bikeshop|mechanic_jobs?|bike_workshop)(?:\/|_|$)/u,
      /mechanic_job/u,
    )
  ) {
    return "workshop";
  }
  if (
    matches(
      /(?:^|\/)(?:inventory|inventario|products?|product_sets?|stock)(?:\/|_|$)/u,
      /product_availability/u,
    )
  ) {
    return "inventory";
  }
  if (
    matches(
      /(?:^|\/)(?:sales?|pos|payments?|checkout|customers?)(?:\/|_|$)/u,
      /sales_invoice/u,
    )
  ) {
    return "sales";
  }
  if (
    matches(
      /(?:^|\/)(?:purchases?|suppliers?|purchase_orders?)(?:\/|_|$)/u,
      /purchase_invoice/u,
    )
  ) {
    return "purchases";
  }
  if (
    matches(/(?:^|\/)(?:hr|workers?|payroll|attendance|employees?)(?:\/|_|$)/u)
  ) {
    return "hr";
  }
  if (
    matches(
      /(?:^|\/)(?:messaging|messages?|chat|whatsapp|meta_messaging)(?:\/|_|$)/u,
    )
  ) {
    return "messaging";
  }
  if (matches(/(?:^|\/)(?:mail|email|gmail|outlook)(?:\/|_|$)/u)) {
    return "mail";
  }
  if (
    matches(
      /(?:^|\/)(?:website|storefront|public_store|merchant|seo)(?:\/|_|$)/u,
      /main_store/u,
    )
  ) {
    return "website";
  }
  if (
    matches(/(?:^|\/)(?:storage|files?|documents?|uploads?|media)(?:\/|_|$)/u)
  ) {
    return "storage";
  }
  if (
    matches(
      /(?:^|\/)(?:accounting|finance|expenses?|journals?|ledger)(?:\/|_|$)/u,
    )
  ) {
    return "accounting";
  }
  if (
    matches(/(?:^|\/)(?:settings?|configuration|preferences?|auth)(?:\/|_|$)/u)
  ) {
    return "settings";
  }
  return "general";
}

function topicForReleasePath(filePath, moduleId) {
  const value = filePath.toLowerCase();
  if (
    /(?:desktop[_-]?update|install_vinabike|macos[_-]?release|publish[_-]?(?:macos|windows)|release[_-]?notes|windows[_-]?release)/u.test(
      value,
    )
  ) {
    return "desktop_updates";
  }
  if (
    /(?:notification|notifications|notificacion|notificaciones)/u.test(value)
  ) {
    return "notifications";
  }
  return DEFAULT_TOPIC_BY_MODULE[moduleId] ?? "general_experience";
}

export function collectReleaseInventory({
  repoDir = process.cwd(),
  fromCommit,
  toCommit,
}) {
  const exactFromCommit = assertCommit(repoDir, fromCommit, "from-commit");
  const exactToCommit = assertCommit(repoDir, toCommit, "to-commit");
  if (exactFromCommit === exactToCommit) {
    throw new Error("The release commit range does not contain any changes.");
  }
  if (!isAncestor(repoDir, exactFromCommit, exactToCommit)) {
    throw new Error("from-commit must be an ancestor of to-commit.");
  }

  const nameStatus = git(
    repoDir,
    [
      "diff",
      "--name-status",
      "-z",
      "--find-renames",
      exactFromCommit,
      exactToCommit,
    ],
    { encoding: "buffer" },
  );
  const numstat = git(
    repoDir,
    ["diff", "--numstat", "-z", "--no-renames", exactFromCommit, exactToCommit],
    { encoding: "buffer" },
  );
  const stats = parseNumstat(numstat);
  const allChanges = parseNameStatus(nameStatus)
    .filter((entry) => isSafeRepoRelativePath(entry.path))
    .map((entry) => {
      const currentStats = stats.get(entry.path);
      const previousStats = entry.previous_path
        ? stats.get(entry.previous_path)
        : undefined;
      return {
        ...entry,
        additions:
          currentStats?.additions ??
          (entry.status === "deleted" ? previousStats?.additions : null) ??
          null,
        deletions:
          currentStats?.deletions ??
          (entry.status === "deleted" ? previousStats?.deletions : null) ??
          null,
        binary: Boolean(currentStats?.binary || previousStats?.binary),
        module_id: moduleForReleasePath(entry.path),
      };
    });

  if (allChanges.length === 0) {
    throw new Error("The release commit range has no changed paths.");
  }

  const aiChanges = allChanges
    .filter(
      (entry) =>
        !entry.binary &&
        !isBinaryReleasePath(entry.path) &&
        !isSensitiveReleasePath(entry.path) &&
        !isGeneratedReleasePath(entry.path) &&
        (!entry.previous_path ||
          (!isSensitiveReleasePath(entry.previous_path) &&
            !isGeneratedReleasePath(entry.previous_path) &&
            !isBinaryReleasePath(entry.previous_path))),
    )
    .slice(0, MAX_PROMPT_CHANGES);

  return {
    from_commit: exactFromCommit,
    to_commit: exactToCommit,
    commits: parseCommitSubjects(repoDir, exactFromCommit, exactToCommit),
    commit_count: Number.parseInt(
      git(repoDir, [
        "rev-list",
        "--count",
        `${exactFromCommit}..${exactToCommit}`,
      ]).trim(),
      10,
    ),
    all_changes: allChanges,
    ai_changes: aiChanges,
    omitted_ai_change_count: Math.max(0, allChanges.length - aiChanges.length),
  };
}

function compareModuleGroups(left, right) {
  const sizeDifference = right.entries.length - left.entries.length;
  if (sizeDifference !== 0) return sizeDifference;
  return (
    (MODULE_ORDER_INDEX.get(left.id) ?? MODULE_ORDER.length) -
    (MODULE_ORDER_INDEX.get(right.id) ?? MODULE_ORDER.length)
  );
}

function groupFallbackChanges(inventory) {
  const evidenceChanges = inventory.ai_changes;
  if (evidenceChanges.length === 0) {
    return [{ id: "general", entries: [] }];
  }
  const grouped = new Map();
  for (const entry of evidenceChanges) {
    const moduleId = entry.module_id;
    const values = grouped.get(moduleId) ?? [];
    values.push(entry);
    grouped.set(moduleId, values);
  }

  let groups = [...grouped.entries()]
    .map(([id, entries]) => ({ id, entries }))
    .sort(compareModuleGroups);

  if (groups.length > 5) {
    const kept = groups.slice(0, 4);
    const remainingEntries = groups.slice(4).flatMap((group) => group.entries);
    const existingGeneral = kept.find((group) => group.id === "general");
    if (existingGeneral) {
      existingGeneral.entries.push(...remainingEntries);
    } else {
      kept.push({ id: "general", entries: remainingEntries });
    }
    groups = kept;
  }
  return groups;
}

export function createFallbackReleaseNotes(inventory) {
  const groups = groupFallbackChanges(inventory);
  const labels = groups.map((group) => RELEASE_NOTE_MODULES[group.id]);
  const moduleSummary =
    labels.length === 1
      ? labels[0]
      : `${labels.slice(0, -1).join(", ")} y ${labels.at(-1)}`;

  return {
    schema_version: 1,
    locale: "es-CL",
    source: "fallback",
    from_commit: inventory.from_commit,
    to_commit: inventory.to_commit,
    title: "Novedades de esta actualización",
    summary: `Esta actualización incluye ajustes en ${moduleSummary}.`,
    modules: groups.map((group) => ({
      id: group.id,
      label: RELEASE_NOTE_MODULES[group.id],
      items: [FALLBACK_ITEMS[group.id]],
      evidence_paths: [
        ...new Set(group.entries.map((entry) => entry.path)),
      ].slice(0, 12),
    })),
  };
}

function hasExactlyKeys(value, expectedKeys) {
  const actual = Object.keys(value).sort();
  const expected = [...expectedKeys].sort();
  return (
    actual.length === expected.length &&
    actual.every((key, index) => key === expected[index])
  );
}

function isBoundedString(value, maximumLength) {
  return (
    typeof value === "string" &&
    value.trim() === value &&
    value.length > 0 &&
    value.length <= maximumLength
  );
}

function containsPrivateIdentifier(value) {
  if (/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/iu.test(value)) {
    return true;
  }
  if (/\b(?:[0-9]{1,2}(?:\.[0-9]{3}){2}|[0-9]{7,8})-[0-9k]\b/iu.test(value)) {
    return true;
  }
  const numericCandidates =
    value.match(/\+?[0-9](?:[0-9\s().-]*[0-9])?/gu) ?? [];
  if (
    numericCandidates.some(
      (candidate) => (candidate.match(/[0-9]/gu) ?? []).length >= 8,
    )
  ) {
    return true;
  }
  return /\b(?:fac|inv|ord|oc|po|ped|cli|customer|cliente|factura|invoice|order|pedido)[\s#:_-]*[a-z]{0,8}[-_]?[0-9]{2,}\b/iu.test(
    value,
  );
}

function isPlainUserText(value) {
  if (!isBoundedString(value, 280)) return false;
  if (/[\r\n\t<>`]/u.test(value)) return false;
  if (/(?:https?:\/\/|www\.)/iu.test(value)) return false;
  if (/(?:^|\s)[#>*+-]\s/u.test(value)) return false;
  if (/\[[^\]]+\]\([^)]+\)/u.test(value)) return false;
  if (/(?:\*\*|__|~~)/u.test(value)) return false;
  if (/(?:^|\s)[\w.-]+\/[\w./-]+/u.test(value)) return false;
  if (
    /\b[\w-]+\.(?:dart|js|mjs|sql|json|ya?ml|sh|ps1|plist|lock)\b/iu.test(value)
  ) {
    return false;
  }
  if (/\b[0-9a-f]{7,40}\b/iu.test(value)) return false;
  if (containsPrivateIdentifier(value)) return false;
  return !/\b(?:api|backend|commit|dart|deploy(?:ment)?|endpoint|frontend|flutter|github|json|pipeline|rpc|schema|sha|sql|supabase|workflow|yaml)\b/iu.test(
    value,
  );
}

function assertReleaseNotesShape(
  notes,
  {
    expectedFromCommit,
    expectedToCommit,
    allowedEvidencePaths,
    allowEmptyFallbackEvidence,
  },
) {
  if (
    !notes ||
    typeof notes !== "object" ||
    Array.isArray(notes) ||
    !hasExactlyKeys(notes, [
      "schema_version",
      "locale",
      "source",
      "from_commit",
      "to_commit",
      "title",
      "summary",
      "modules",
    ])
  ) {
    throw new Error("Release notes have an invalid top-level shape.");
  }
  if (
    notes.schema_version !== 1 ||
    notes.locale !== "es-CL" ||
    !["ai", "fallback"].includes(notes.source) ||
    notes.from_commit !== expectedFromCommit ||
    notes.to_commit !== expectedToCommit
  ) {
    throw new Error("Release notes do not match the exact release range.");
  }
  if (
    !isBoundedString(notes.title, 80) ||
    !isPlainUserText(notes.title) ||
    !isBoundedString(notes.summary, 280) ||
    !isPlainUserText(notes.summary)
  ) {
    throw new Error("Release-note title or summary is invalid.");
  }
  if (
    !Array.isArray(notes.modules) ||
    notes.modules.length < 1 ||
    notes.modules.length > 5
  ) {
    throw new Error("Release notes must contain between one and five modules.");
  }

  const seenModules = new Set();
  for (const module of notes.modules) {
    if (
      !module ||
      typeof module !== "object" ||
      Array.isArray(module) ||
      !hasExactlyKeys(module, ["id", "label", "items", "evidence_paths"])
    ) {
      throw new Error("A release-note module has an invalid shape.");
    }
    if (
      !Object.hasOwn(RELEASE_NOTE_MODULES, module.id) ||
      module.label !== RELEASE_NOTE_MODULES[module.id] ||
      seenModules.has(module.id)
    ) {
      throw new Error("A release-note module is unsupported or duplicated.");
    }
    seenModules.add(module.id);

    if (
      !Array.isArray(module.items) ||
      module.items.length < 1 ||
      module.items.length > 3 ||
      module.items.some(
        (item) => !isBoundedString(item, 160) || !isPlainUserText(item),
      )
    ) {
      throw new Error("A release-note item is invalid.");
    }
    const evidenceIsArray = Array.isArray(module.evidence_paths);
    const hasAllowedEmptyFallbackEvidence =
      evidenceIsArray &&
      allowEmptyFallbackEvidence &&
      module.id === "general" &&
      module.evidence_paths.length === 0;
    if (
      !evidenceIsArray ||
      (!hasAllowedEmptyFallbackEvidence && module.evidence_paths.length < 1) ||
      module.evidence_paths.length > 12 ||
      new Set(module.evidence_paths).size !== module.evidence_paths.length ||
      module.evidence_paths.some(
        (evidencePath) =>
          !isSafeRepoRelativePath(evidencePath) ||
          !allowedEvidencePaths.has(evidencePath),
      )
    ) {
      throw new Error("A release-note module cites unsupported evidence.");
    }
    if (
      notes.source === "ai" &&
      !module.evidence_paths.some(
        (evidencePath) => moduleForReleasePath(evidencePath) === module.id,
      )
    ) {
      throw new Error("A release-note module does not match its evidence.");
    }
  }
}

export function validateReleaseNotes(
  notes,
  { inventory, source = notes?.source } = {},
) {
  if (!inventory) throw new Error("Release inventory is required.");
  const evidenceEntries = inventory.ai_changes;
  const allowedEvidencePaths = new Set(
    evidenceEntries.flatMap((entry) => [
      entry.path,
      ...(entry.previous_path ? [entry.previous_path] : []),
    ]),
  );
  assertReleaseNotesShape(notes, {
    expectedFromCommit: inventory.from_commit,
    expectedToCommit: inventory.to_commit,
    allowedEvidencePaths,
    allowEmptyFallbackEvidence:
      source === "fallback" && inventory.ai_changes.length === 0,
  });
  return notes;
}

function aiOutputSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["title", "summary", "modules"],
    properties: {
      title: {
        type: "string",
        minLength: 1,
        maxLength: 80,
      },
      summary: {
        type: "string",
        minLength: 1,
        maxLength: 280,
      },
      modules: {
        type: "array",
        minItems: 1,
        maxItems: 5,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["id", "label", "items", "evidence_ids"],
          properties: {
            id: {
              type: "string",
              enum: MODULE_ORDER,
            },
            label: {
              type: "string",
              enum: Object.values(RELEASE_NOTE_MODULES),
            },
            items: {
              type: "array",
              minItems: 1,
              maxItems: 3,
              items: {
                type: "string",
                minLength: 1,
                maxLength: 160,
              },
            },
            evidence_ids: {
              type: "array",
              minItems: 1,
              maxItems: 12,
              items: {
                type: "string",
              },
            },
          },
        },
      },
    },
  };
}

const AI_EDITOR_INSTRUCTIONS = [
  "Eres editor de novedades para personas que usan un ERP de bicicletería en Chile.",
  "Resume únicamente los metadatos entregados; no inventes cambios, beneficios ni módulos.",
  "Usa español de Chile simple, directo y no técnico.",
  "No uses Markdown, HTML, enlaces, nombres de archivos, rutas, hashes ni jerga de desarrollo.",
  "Cada módulo debe citar evidence_ids exactos de changes y usar el id y label canónicos correspondientes.",
  "Prioriza cambios visibles para usuarios. Si el metadato no permite una afirmación específica, describe un ajuste de estabilidad con prudencia.",
].join(" ");

function buildEvidenceCatalog(inventory) {
  return inventory.ai_changes.map((entry, index) => {
    const evidenceId = `change_${String(index + 1).padStart(3, "0")}`;
    const topicId = topicForReleasePath(entry.path, entry.module_id);
    return {
      evidence_id: evidenceId,
      module_id: entry.module_id,
      topic_id: topicId,
      status: entry.status,
      additions: entry.additions,
      deletions: entry.deletions,
      local_path: entry.path,
    };
  });
}

function buildAiMetadata(inventory) {
  const evidenceCatalog = buildEvidenceCatalog(inventory);
  return {
    locale: "es-CL",
    commit_count: inventory.commit_count,
    change_count: inventory.all_changes.length,
    included_change_count: evidenceCatalog.length,
    omitted_or_protected_change_count: inventory.omitted_ai_change_count,
    module_labels: RELEASE_NOTE_MODULES,
    topic_labels: RELEASE_NOTE_TOPICS,
    changes: evidenceCatalog.map((entry) => ({
      evidence_id: entry.evidence_id,
      module_id: entry.module_id,
      topic_id: entry.topic_id,
      status: entry.status,
      additions: entry.additions,
      deletions: entry.deletions,
    })),
  };
}

function buildOpenAiRequest(inventory, model) {
  return {
    model,
    max_output_tokens: 1_200,
    input: [
      {
        role: "system",
        content: [
          {
            type: "input_text",
            text: AI_EDITOR_INSTRUCTIONS,
          },
        ],
      },
      {
        role: "user",
        content: [
          {
            type: "input_text",
            text: JSON.stringify(buildAiMetadata(inventory)),
          },
        ],
      },
    ],
    text: {
      format: {
        type: "json_schema",
        name: "vinabike_desktop_release_notes_by_evidence_id",
        strict: true,
        schema: aiOutputSchema(),
      },
    },
  };
}

function geminiAiOutputSchema() {
  const schema = structuredClone(aiOutputSchema());
  delete schema.properties.title.minLength;
  delete schema.properties.title.maxLength;
  delete schema.properties.summary.minLength;
  delete schema.properties.summary.maxLength;
  delete schema.properties.modules.items.properties.items.items.minLength;
  delete schema.properties.modules.items.properties.items.items.maxLength;
  return schema;
}

function buildGeminiRequest(inventory) {
  return {
    systemInstruction: {
      parts: [{ text: AI_EDITOR_INSTRUCTIONS }],
    },
    contents: [
      {
        role: "user",
        parts: [{ text: JSON.stringify(buildAiMetadata(inventory)) }],
      },
    ],
    generationConfig: {
      maxOutputTokens: 1_200,
      responseFormat: {
        text: {
          mimeType: "application/json",
          schema: geminiAiOutputSchema(),
        },
      },
    },
  };
}

function extractOpenAiModelOutput(payload) {
  if (typeof payload?.output_text === "string") {
    return payload.output_text;
  }
  if (!Array.isArray(payload?.output)) return null;

  for (const outputItem of payload.output) {
    if (!Array.isArray(outputItem?.content)) continue;
    for (const contentItem of outputItem.content) {
      if (
        contentItem?.type === "output_text" &&
        typeof contentItem.text === "string"
      ) {
        return contentItem.text;
      }
    }
  }
  return null;
}

function extractGeminiModelOutput(payload) {
  if (!Array.isArray(payload?.candidates)) return null;
  for (const candidate of payload.candidates) {
    if (!Array.isArray(candidate?.content?.parts)) continue;
    const text = candidate.content.parts
      .filter(
        (part) => part?.thought !== true && typeof part?.text === "string",
      )
      .map((part) => part.text)
      .join("");
    if (text) return text;
  }
  return null;
}

function normalizeGeminiModel(model) {
  if (
    typeof model !== "string" ||
    !GEMINI_MODEL_PATTERN.test(model.trim().toLowerCase())
  ) {
    return null;
  }
  return model.trim().toLowerCase();
}

function geminiEndpoint(model) {
  const normalizedModel = normalizeGeminiModel(model);
  if (!normalizedModel) return null;
  return `${GEMINI_ENDPOINT_ROOT}/${encodeURIComponent(normalizedModel)}:generateContent`;
}

function geminiModelNames(payload) {
  if (!Array.isArray(payload?.models)) return new Set();
  const names = new Set();
  for (const model of payload.models) {
    const methods = Array.isArray(model?.supportedGenerationMethods)
      ? model.supportedGenerationMethods
      : Array.isArray(model?.supportedActions)
        ? model.supportedActions
        : [];
    if (!methods.includes("generateContent")) continue;

    for (const value of [model?.baseModelId, model?.name]) {
      if (typeof value !== "string") continue;
      const withoutPrefix = value.startsWith("models/")
        ? value.slice("models/".length)
        : value;
      const normalized = normalizeGeminiModel(withoutPrefix);
      if (normalized) names.add(normalized);
    }
  }
  return names;
}

async function discoverGeminiFallbackModel({
  apiKey,
  currentModel,
  fetchImpl,
  timeoutMs,
}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  timeout.unref?.();
  try {
    const response = await fetchImpl(GEMINI_MODELS_ENDPOINT, {
      method: "GET",
      headers: {
        "x-goog-api-key": apiKey,
      },
      signal: controller.signal,
    });
    if (!response.ok) return null;

    const contentLength = Number.parseInt(
      response.headers.get("content-length") ?? "0",
      10,
    );
    if (contentLength > MAX_API_RESPONSE_BYTES) return null;
    const responseText = await response.text();
    if (Buffer.byteLength(responseText, "utf8") > MAX_API_RESPONSE_BYTES) {
      return null;
    }

    let payload;
    try {
      payload = JSON.parse(responseText);
    } catch {
      return null;
    }
    const availableModels = geminiModelNames(payload);
    const normalizedCurrent = normalizeGeminiModel(currentModel);
    return (
      GEMINI_FALLBACK_MODELS.find(
        (candidate) =>
          candidate !== normalizedCurrent && availableModels.has(candidate),
      ) ?? null
    );
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function validatedEndpoint(value) {
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    return null;
  }
  if (parsed.href === DEFAULT_ENDPOINT) return parsed.href;
  if (
    parsed.protocol === "http:" &&
    ["127.0.0.1", "localhost", "::1", "[::1]"].includes(parsed.hostname)
  ) {
    return parsed.href;
  }
  return null;
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(maximum, Math.max(minimum, parsed));
}

function shouldDiscoverGeminiFallback(reason) {
  return (
    typeof reason === "string" &&
    (reason === "http_400_invalid_argument" || reason.startsWith("http_404"))
  );
}

async function sanitizedHttpFailureReason(response) {
  const baseReason = `http_${response.status}`;
  const contentLength = Number.parseInt(
    response.headers.get("content-length") ?? "0",
    10,
  );
  if (contentLength > MAX_API_RESPONSE_BYTES) return baseReason;

  let responseText;
  try {
    responseText = await response.text();
  } catch {
    return baseReason;
  }
  if (Buffer.byteLength(responseText, "utf8") > MAX_API_RESPONSE_BYTES) {
    return baseReason;
  }

  let payload;
  try {
    payload = JSON.parse(responseText);
  } catch {
    return baseReason;
  }
  const status =
    typeof payload?.error?.status === "string"
      ? payload.error.status.trim().toUpperCase()
      : "";
  const category = SAFE_API_ERROR_CATEGORIES.get(status);
  return category ? `${baseReason}_${category}` : baseReason;
}

async function requestAiCandidate({
  requestBody,
  requestHeaders,
  endpoint,
  extractModelOutput,
  fetchImpl,
  timeoutMs,
}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  timeout.unref?.();
  try {
    const response = await fetchImpl(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...requestHeaders,
      },
      body: JSON.stringify(requestBody),
      signal: controller.signal,
    });

    if (!response.ok) {
      return {
        candidate: null,
        reason: await sanitizedHttpFailureReason(response),
        retryable:
          response.status === 408 ||
          response.status === 409 ||
          response.status === 429 ||
          response.status >= 500,
      };
    }

    const contentLength = Number.parseInt(
      response.headers.get("content-length") ?? "0",
      10,
    );
    if (contentLength > MAX_API_RESPONSE_BYTES) {
      return {
        candidate: null,
        reason: "oversized_response",
        retryable: false,
      };
    }

    const responseText = await response.text();
    if (Buffer.byteLength(responseText, "utf8") > MAX_API_RESPONSE_BYTES) {
      return {
        candidate: null,
        reason: "oversized_response",
        retryable: false,
      };
    }

    let payload;
    try {
      payload = JSON.parse(responseText);
    } catch {
      return {
        candidate: null,
        reason: "malformed_api_json",
        retryable: false,
      };
    }

    const modelOutput = extractModelOutput(payload);
    if (
      typeof modelOutput !== "string" ||
      modelOutput.length > MAX_MODEL_OUTPUT_CHARS
    ) {
      return {
        candidate: null,
        reason: "missing_or_oversized_model_output",
        retryable: false,
      };
    }

    let candidate;
    try {
      candidate = JSON.parse(modelOutput);
    } catch {
      return {
        candidate: null,
        reason: "malformed_model_json",
        retryable: false,
      };
    }

    return { candidate, reason: null, retryable: false };
  } catch (error) {
    return {
      candidate: null,
      reason: error?.name === "AbortError" ? "timeout" : "network_error",
      retryable: true,
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function writeJsonAtomically(outputPath, value) {
  const resolvedOutput = path.resolve(outputPath);
  await mkdir(path.dirname(resolvedOutput), { recursive: true });
  const temporaryPath = `${resolvedOutput}.tmp-${process.pid}-${Date.now()}`;
  await writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
  await rename(temporaryPath, resolvedOutput);
}

function wrapAiCandidate(candidate, inventory) {
  if (
    !candidate ||
    typeof candidate !== "object" ||
    Array.isArray(candidate) ||
    !hasExactlyKeys(candidate, ["title", "summary", "modules"]) ||
    !Array.isArray(candidate.modules) ||
    candidate.modules.length < 1 ||
    candidate.modules.length > 5
  ) {
    throw new Error("The AI candidate has an invalid shape.");
  }

  const evidenceById = new Map(
    buildEvidenceCatalog(inventory).map((entry) => [entry.evidence_id, entry]),
  );
  const seenModules = new Set();
  const modules = candidate.modules.map((module) => {
    if (
      !module ||
      typeof module !== "object" ||
      Array.isArray(module) ||
      !hasExactlyKeys(module, ["id", "label", "items", "evidence_ids"]) ||
      !Object.hasOwn(RELEASE_NOTE_MODULES, module.id) ||
      module.label !== RELEASE_NOTE_MODULES[module.id] ||
      seenModules.has(module.id) ||
      !Array.isArray(module.evidence_ids) ||
      module.evidence_ids.length < 1 ||
      module.evidence_ids.length > 12 ||
      new Set(module.evidence_ids).size !== module.evidence_ids.length
    ) {
      throw new Error("The AI candidate has invalid evidence IDs.");
    }
    seenModules.add(module.id);

    const evidenceEntries = module.evidence_ids.map((evidenceId) => {
      if (
        typeof evidenceId !== "string" ||
        !/^change_[0-9]{3}$/u.test(evidenceId)
      ) {
        throw new Error("The AI candidate has an invalid evidence ID.");
      }
      const evidenceEntry = evidenceById.get(evidenceId);
      if (!evidenceEntry || evidenceEntry.module_id !== module.id) {
        throw new Error("The AI candidate cites unsupported evidence.");
      }
      return evidenceEntry;
    });

    return {
      id: module.id,
      label: module.label,
      items: module.items,
      evidence_paths: evidenceEntries.map((entry) => entry.local_path),
    };
  });

  return {
    schema_version: 1,
    locale: "es-CL",
    source: "ai",
    from_commit: inventory.from_commit,
    to_commit: inventory.to_commit,
    title: candidate.title,
    summary: candidate.summary,
    modules,
  };
}

export async function generateReleaseNotes({
  repoDir = process.cwd(),
  fromCommit,
  toCommit,
  outputPath,
  apiKey = "",
  model = DEFAULT_MODEL,
  endpoint = DEFAULT_ENDPOINT,
  geminiApiKey = "",
  geminiModel = DEFAULT_GEMINI_MODEL,
  fetchImpl = globalThis.fetch,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  maxAttempts = DEFAULT_MAX_ATTEMPTS,
} = {}) {
  if (!outputPath) throw new Error("An output path is required.");
  const inventory = collectReleaseInventory({
    repoDir,
    fromCommit,
    toCommit,
  });
  const fallback = createFallbackReleaseNotes(inventory);
  validateReleaseNotes(fallback, { inventory, source: "fallback" });

  const envelope = { release_notes: fallback };
  await writeJsonAtomically(outputPath, envelope);

  const provider = geminiApiKey ? "gemini" : apiKey ? "openai" : null;
  if (!provider) {
    return {
      source: "fallback",
      reason: "missing_api_key",
      inventory,
      release_notes: fallback,
    };
  }
  if (typeof fetchImpl !== "function") {
    return {
      source: "fallback",
      reason: "fetch_unavailable",
      inventory,
      release_notes: fallback,
    };
  }
  if (inventory.ai_changes.length === 0) {
    return {
      source: "fallback",
      reason: "no_safe_ai_metadata",
      inventory,
      release_notes: fallback,
    };
  }

  const safeEndpoint =
    provider === "gemini"
      ? geminiEndpoint(geminiModel)
      : validatedEndpoint(endpoint);
  if (!safeEndpoint) {
    return {
      source: "fallback",
      reason: provider === "gemini" ? "invalid_model" : "invalid_endpoint",
      inventory,
      release_notes: fallback,
    };
  }

  const attempts = boundedInteger(maxAttempts, DEFAULT_MAX_ATTEMPTS, 1, 2);
  const boundedTimeout = boundedInteger(
    timeoutMs,
    DEFAULT_TIMEOUT_MS,
    1,
    30_000,
  );
  let activeGeminiModel = normalizeGeminiModel(geminiModel);
  let activeEndpoint = safeEndpoint;
  let finalReason = "ai_unavailable";
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const result = await requestAiCandidate({
      requestBody:
        provider === "gemini"
          ? buildGeminiRequest(inventory)
          : buildOpenAiRequest(inventory, model),
      requestHeaders:
        provider === "gemini"
          ? { "x-goog-api-key": geminiApiKey }
          : { Authorization: `Bearer ${apiKey}` },
      endpoint: activeEndpoint,
      extractModelOutput:
        provider === "gemini"
          ? extractGeminiModelOutput
          : extractOpenAiModelOutput,
      fetchImpl,
      timeoutMs: boundedTimeout,
    });
    finalReason = result.reason ?? finalReason;
    if (result.candidate) {
      try {
        const aiNotes = wrapAiCandidate(result.candidate, inventory);
        validateReleaseNotes(aiNotes, { inventory, source: "ai" });
        try {
          await writeJsonAtomically(outputPath, { release_notes: aiNotes });
        } catch {
          return {
            source: "fallback",
            reason: "ai_output_write_failed",
            inventory,
            release_notes: fallback,
          };
        }
        return {
          source: "ai",
          reason: null,
          provider,
          model: provider === "gemini" ? activeGeminiModel : null,
          inventory,
          release_notes: aiNotes,
        };
      } catch {
        finalReason = "invalid_ai_release_notes";
        break;
      }
    }
    if (
      provider === "gemini" &&
      shouldDiscoverGeminiFallback(result.reason) &&
      attempt < attempts
    ) {
      const fallbackModel = await discoverGeminiFallbackModel({
        apiKey: geminiApiKey,
        currentModel: activeGeminiModel,
        fetchImpl,
        timeoutMs: boundedTimeout,
      });
      const fallbackEndpoint = geminiEndpoint(fallbackModel);
      if (fallbackModel && fallbackEndpoint) {
        activeGeminiModel = fallbackModel;
        activeEndpoint = fallbackEndpoint;
        continue;
      }
    }
    if (!result.retryable || attempt === attempts) break;
  }

  return {
    source: "fallback",
    reason: finalReason,
    provider,
    model: provider === "gemini" ? activeGeminiModel : null,
    inventory,
    release_notes: fallback,
  };
}

function parseCliArgs(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") {
      return { help: true };
    }
    if (!["--from-commit", "--to-commit", "--output"].includes(argument)) {
      throw new Error(`Unknown argument: ${argument}`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for ${argument}.`);
    }
    values[argument.slice(2).replaceAll("-", "_")] = value;
    index += 1;
  }
  if (!values.from_commit || !values.to_commit || !values.output) {
    throw new Error(
      "--from-commit, --to-commit, and --output are all required.",
    );
  }
  return values;
}

function printUsage() {
  process.stdout.write(
    [
      "Usage:",
      "  node scripts/releases/generate_release_notes.mjs \\",
      "    --from-commit <40-character-sha> \\",
      "    --to-commit <40-character-sha> \\",
      "    --output <release-notes.json>",
      "",
      "Optional environment:",
      "  GEMINI_RELEASE_API_KEY (preferred when present)",
      "  GEMINI_RELEASE_NOTES_MODEL (default: gemini-3.1-flash-lite)",
      "  OPENAI_API_KEY",
      "  OPENAI_RELEASE_NOTES_MODEL (default: gpt-5-mini)",
      "",
    ].join("\n"),
  );
}

async function main() {
  const args = parseCliArgs(process.argv.slice(2));
  if (args.help) {
    printUsage();
    return;
  }

  const result = await generateReleaseNotes({
    repoDir: process.cwd(),
    fromCommit: args.from_commit,
    toCommit: args.to_commit,
    outputPath: args.output,
    geminiApiKey: process.env.GEMINI_RELEASE_API_KEY ?? "",
    geminiModel: process.env.GEMINI_RELEASE_NOTES_MODEL || DEFAULT_GEMINI_MODEL,
    apiKey: process.env.OPENAI_API_KEY ?? "",
    model: process.env.OPENAI_RELEASE_NOTES_MODEL || DEFAULT_MODEL,
    endpoint: process.env.OPENAI_RELEASE_NOTES_ENDPOINT || DEFAULT_ENDPOINT,
    timeoutMs: process.env.OPENAI_RELEASE_NOTES_TIMEOUT_MS,
    maxAttempts: process.env.OPENAI_RELEASE_NOTES_MAX_ATTEMPTS,
  });
  const suffix = result.reason ? ` (${result.reason})` : "";
  const modelSuffix =
    result.provider === "gemini" && result.model
      ? `; Gemini model: ${result.model}`
      : "";
  process.stdout.write(
    `Release notes source: ${result.source}${suffix}${modelSuffix}; wrote ${path.resolve(args.output)}\n`,
  );
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === currentFile) {
  main().catch((error) => {
    const message =
      error instanceof Error ? error.message : "Unknown release-note error.";
    process.stderr.write(`Release-note generation failed: ${message}\n`);
    process.exitCode = 1;
  });
}
