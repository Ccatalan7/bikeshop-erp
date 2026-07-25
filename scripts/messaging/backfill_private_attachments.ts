const PROJECT_REF = "xzdvtzdqjeyqxnkqprtf";
const DEFAULT_SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;
const PUBLIC_BUCKET = "vinabike-assets";
const PRIVATE_BUCKET = "chat-attachments";
const QUARANTINE_BUCKET = "messaging-attachment-quarantine";
const MAX_SCOPE_OBJECTS = 100;
const MAX_CANDIDATES = 100;
const MAX_AUDIT_BYTES = 64 * 1024 * 1024;

type JsonRecord = Record<string, unknown>;

interface LegacyCandidate {
  message_id: string;
  tenant_id: string;
  conversation_id: string;
  legacy_url: string;
  distinct_legacy_url_count: number;
  message_type: string;
  message_created_at: string;
  metadata: JsonRecord;
}

interface LegacyObject {
  storage_path: string;
  object_created_at: string;
  object_updated_at: string;
  object_metadata: JsonRecord;
}

interface ObjectAudit {
  path: string;
  sha256: string;
  sizeBytes: number;
  contentType: string;
  createdAt: Date;
  referenceCount: number;
}

const mimeByExtension: Readonly<Record<string, string>> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  gif: "image/gif",
  webp: "image/webp",
  pdf: "application/pdf",
  doc: "application/msword",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  xls: "application/vnd.ms-excel",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  txt: "text/plain",
  mp4: "video/mp4",
  "3gp": "video/3gpp",
  mp3: "audio/mpeg",
  ogg: "audio/ogg",
  m4a: "audio/mp4",
  aac: "audio/aac",
};

function parseArguments(args: string[]) {
  let execute = false;
  let confirmation = "";
  let expectedFingerprint = "";
  let minOrphanAgeHours = 24;
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--execute") {
      execute = true;
    } else if (argument === "--confirm") {
      confirmation = args[++index] ?? "";
    } else if (argument === "--expected-fingerprint") {
      expectedFingerprint = args[++index] ?? "";
    } else if (argument === "--min-orphan-age-hours") {
      minOrphanAgeHours = Number(args[++index] ?? "");
    } else if (argument === "--help") {
      console.log(
        "Usage: backfill_private_attachments.sh [--execute --confirm production --expected-fingerprint SHA256] [--min-orphan-age-hours 24]",
      );
      Deno.exit(0);
    } else {
      throw new Error("invalid_argument");
    }
  }
  if (!Number.isFinite(minOrphanAgeHours) || minOrphanAgeHours < 24) {
    throw new Error("minimum_orphan_age_must_be_at_least_24_hours");
  }
  if (execute) {
    if (
      confirmation !== "production" ||
      Deno.env.get("VINABIKE_STORAGE_BACKFILL_CONFIRM") !== "production"
    ) {
      throw new Error("production_confirmation_required");
    }
    if (!/^[0-9a-f]{64}$/.test(expectedFingerprint)) {
      throw new Error("dry_run_fingerprint_required");
    }
  }
  return { execute, expectedFingerprint, minOrphanAgeHours };
}

const options = parseArguments(Deno.args);
const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? DEFAULT_SUPABASE_URL)
  .replace(/\/+$/, "");
const serviceKey = Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
if (new URL(supabaseUrl).host !== `${PROJECT_REF}.supabase.co`) {
  throw new Error("unexpected_supabase_project");
}
if (!serviceKey) throw new Error("missing_supabase_secret_key");

function encodedStoragePath(path: string) {
  return path.split("/").map(encodeURIComponent).join("/");
}

function authHeaders(extra?: HeadersInit) {
  const headers = new Headers(extra);
  headers.set("apikey", serviceKey);
  return headers;
}

async function rpc<T>(name: string, body: JsonRecord = {}): Promise<T> {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: authHeaders({ "Content-Type": "application/json" }),
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`rpc_${name}_${response.status}`);
  return await response.json() as T;
}

async function restRows<T>(resourceAndQuery: string): Promise<T[]> {
  const response = await fetch(`${supabaseUrl}/rest/v1/${resourceAndQuery}`, {
    headers: authHeaders(),
  });
  if (!response.ok) throw new Error(`readback_${response.status}`);
  return await response.json() as T[];
}

async function downloadObject(bucket: string, path: string) {
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/authenticated/${bucket}/${encodedStoragePath(path)}`,
    { headers: authHeaders() },
  );
  if (!response.ok) throw new Error(`storage_download_${response.status}`);
  const announcedLength = Number(response.headers.get("content-length") ?? "");
  if (Number.isFinite(announcedLength) && announcedLength > MAX_AUDIT_BYTES) {
    throw new Error("legacy_object_exceeds_audit_ceiling");
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > MAX_AUDIT_BYTES) {
    throw new Error("legacy_object_exceeds_audit_ceiling");
  }
  return {
    bytes,
    contentType: normalizeContentType(response.headers.get("content-type")),
  };
}

async function uploadPrivateObject(
  bucket: string,
  path: string,
  bytes: Uint8Array,
  contentType: string,
) {
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/${bucket}/${encodedStoragePath(path)}`,
    {
      method: "POST",
      headers: authHeaders({
        "Content-Type": contentType,
        "x-upsert": "false",
      }),
      body: new Blob([bytes.slice().buffer as ArrayBuffer], {
        type: contentType,
      }),
    },
  );
  if (response.ok) return "uploaded";

  // A retry after an acknowledgement loss can legitimately find the
  // deterministic private object already present. Its exact byte readback is
  // the only accepted substitute for a successful upload response.
  try {
    await downloadObject(bucket, path);
    return "already_present";
  } catch (_) {
    throw new Error(`private_upload_${response.status}`);
  }
}

async function deletePublicObjects(paths: string[]) {
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/${PUBLIC_BUCKET}`,
    {
      method: "DELETE",
      headers: authHeaders({ "Content-Type": "application/json" }),
      body: JSON.stringify({ prefixes: paths }),
    },
  );
  if (!response.ok) throw new Error(`public_delete_${response.status}`);
}

function normalizeContentType(value: unknown) {
  return typeof value === "string" ? value.split(";")[0].trim().toLowerCase() : "";
}

function metadataNumber(metadata: JsonRecord, key: string) {
  const parsed = Number(metadata[key] ?? "");
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : null;
}

function legacyPathFromUrl(rawUrl: string) {
  const url = new URL(rawUrl);
  if (url.protocol !== "https:" || url.host !== `${PROJECT_REF}.supabase.co`) {
    throw new Error("untrusted_legacy_url");
  }
  const prefix = `/storage/v1/object/public/${PUBLIC_BUCKET}/`;
  if (!url.pathname.startsWith(prefix)) throw new Error("untrusted_legacy_url");
  let path: string;
  try {
    path = decodeURIComponent(url.pathname.slice(prefix.length));
  } catch (_) {
    throw new Error("invalid_legacy_url_encoding");
  }
  assertLegacyPath(path);
  return path;
}

function assertLegacyPath(path: string) {
  if (
    !(path.startsWith("chat/") || path.startsWith("whatsapp-media/")) ||
    path.includes("\\") ||
    path.includes("\0") ||
    path.split("/").some((segment) => !segment || segment === "." || segment === "..")
  ) {
    throw new Error("unsafe_legacy_storage_path");
  }
}

function extensionForName(name: string) {
  const basename = name.split(/[\\/]/).pop() ?? "";
  const dot = basename.lastIndexOf(".");
  return dot > 0 && dot < basename.length - 1 ? basename.slice(dot + 1).toLowerCase() : "";
}

function safeFilename(candidate: LegacyCandidate, path: string) {
  const metadata = candidate.metadata ?? {};
  const raw = [
    metadata.filename,
    metadata.document_filename,
    metadata.documentFilename,
    path.split("/").pop(),
  ].find((value) => typeof value === "string" && value.trim()) as
    | string
    | undefined;
  // deno-lint-ignore no-control-regex -- intentional legacy C0 sanitization.
  const legacyFilenameControlCharacters = /[\x00-\x1f\x7f]/g;
  const sanitized = (raw ?? "archivo")
    .split(/[\\/]/).pop()!
    .replace(legacyFilenameControlCharacters, "_")
    .trim()
    .slice(0, 200);
  return sanitized || "archivo";
}

function maxBytesForMime(contentType: string) {
  if (contentType.startsWith("image/")) return 5 * 1024 * 1024;
  if (contentType.startsWith("audio/") || contentType.startsWith("video/")) {
    return 16 * 1024 * 1024;
  }
  if (contentType === "text/plain") return 2 * 1024 * 1024;
  return 20 * 1024 * 1024;
}

async function sha256Hex(value: Uint8Array | string) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  const digest = new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      bytes.slice().buffer as ArrayBuffer,
    ),
  );
  return Array.from(digest).map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function deterministicAttachmentId(messageId: string, oldPath: string) {
  const hash = await sha256Hex(
    `vinabike-private-message-v1:${messageId}:${oldPath}`,
  );
  const bytes = Array.from(
    { length: 16 },
    (_, index) => Number.parseInt(hash.slice(index * 2, index * 2 + 2), 16),
  );
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${
    hex.slice(20)
  }`;
}

function candidateContract(
  candidate: LegacyCandidate,
  path: string,
  audit: ObjectAudit,
) {
  const originalFilename = safeFilename(candidate, path);
  const extension = extensionForName(originalFilename) ||
    extensionForName(path);
  const contentType = mimeByExtension[extension];
  if (!contentType) throw new Error("unsupported_referenced_legacy_type");
  if (audit.sizeBytes <= 0 || audit.sizeBytes > maxBytesForMime(contentType)) {
    throw new Error("referenced_legacy_size_out_of_contract");
  }
  if (
    audit.contentType &&
    audit.contentType !== "application/octet-stream" &&
    audit.contentType !== contentType
  ) {
    throw new Error("referenced_legacy_mime_mismatch");
  }
  const filename = extensionForName(originalFilename) === extension
    ? originalFilename
    : `archivo.${extension}`;
  return { filename, extension, contentType };
}

async function auditPublicObject(
  object: LegacyObject,
  referenceCount: number,
): Promise<ObjectAudit> {
  assertLegacyPath(object.storage_path);
  const downloaded = await downloadObject(PUBLIC_BUCKET, object.storage_path);
  const metadataSize = metadataNumber(object.object_metadata ?? {}, "size");
  if (metadataSize != null && metadataSize !== downloaded.bytes.byteLength) {
    throw new Error("legacy_object_size_readback_mismatch");
  }
  const metadataType = normalizeContentType(
    object.object_metadata?.mimetype ?? object.object_metadata?.contentType,
  );
  if (
    metadataType &&
    downloaded.contentType &&
    metadataType !== downloaded.contentType
  ) {
    throw new Error("legacy_object_mime_readback_mismatch");
  }
  const createdAt = new Date(object.object_created_at);
  if (Number.isNaN(createdAt.getTime())) {
    throw new Error("invalid_object_timestamp");
  }
  return {
    path: object.storage_path,
    sha256: await sha256Hex(downloaded.bytes),
    sizeBytes: downloaded.bytes.byteLength,
    contentType: metadataType || downloaded.contentType,
    createdAt,
    referenceCount,
  };
}

async function writeReceipt(receipt: JsonRecord) {
  const directory = ".tmp/messaging-attachments";
  await Deno.mkdir(directory, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const path = `${directory}/legacy-private-backfill-${stamp}.json`;
  const body = `${JSON.stringify(receipt, null, 2)}\n`;
  await Deno.writeTextFile(path, body);
  const hash = await sha256Hex(body);
  await Deno.writeTextFile(
    `${path}.sha256`,
    `${hash}  ${path.split("/").pop()}\n`,
  );
  return { path, hash };
}

async function main() {
  const startedAt = new Date();
  const candidates = await rpc<LegacyCandidate[]>(
    "list_legacy_messaging_attachment_candidates",
  );
  const publicObjects = await rpc<LegacyObject[]>(
    "list_legacy_messaging_public_objects",
  );
  if (
    candidates.length > MAX_CANDIDATES ||
    publicObjects.length > MAX_SCOPE_OBJECTS
  ) {
    throw new Error("legacy_scope_exceeds_reviewed_ceiling");
  }

  const referencesByPath = new Map<string, number>();
  const candidatePath = new Map<string, string>();
  for (const candidate of candidates) {
    if (Number(candidate.distinct_legacy_url_count) !== 1) {
      throw new Error("ambiguous_legacy_message_reference");
    }
    const path = legacyPathFromUrl(candidate.legacy_url);
    candidatePath.set(candidate.message_id, path);
    referencesByPath.set(path, (referencesByPath.get(path) ?? 0) + 1);
  }

  const objectByPath = new Map(
    publicObjects.map((object) => [object.storage_path, object]),
  );
  for (const path of referencesByPath.keys()) {
    if (!objectByPath.has(path)) {
      throw new Error("referenced_public_object_missing");
    }
  }

  const audits = new Map<string, ObjectAudit>();
  for (const object of publicObjects) {
    const audit = await auditPublicObject(
      object,
      referencesByPath.get(object.storage_path) ?? 0,
    );
    audits.set(object.storage_path, audit);
  }
  for (const candidate of candidates) {
    const path = candidatePath.get(candidate.message_id)!;
    candidateContract(candidate, path, audits.get(path)!);
  }

  const fingerprint = await sha256Hex(
    Array.from(audits.values())
      .sort((left, right) => left.path.localeCompare(right.path))
      .map((audit) => `${audit.path}\0${audit.sha256}\0${audit.sizeBytes}\0${audit.referenceCount}`)
      .join("\n"),
  );
  const orphanCount = publicObjects.length - referencesByPath.size;
  const preflight = {
    referenced_messages: candidates.length,
    referenced_public_objects: referencesByPath.size,
    orphan_public_objects: orphanCount,
    public_scope_objects: publicObjects.length,
    aggregate_fingerprint: fingerprint,
    orphan_preservation: "private_content_hash_quarantine_before_delete",
  };

  if (!options.execute) {
    const receipt = await writeReceipt({
      receipt_version: 2,
      project_ref: PROJECT_REF,
      mode: "dry-run",
      status: "verified",
      started_at: startedAt.toISOString(),
      completed_at: new Date().toISOString(),
      preflight,
      planned_private_orphan_quarantine_objects: orphanCount,
      mutations: 0,
      contains_paths_or_pii: false,
    });
    console.log(
      `Dry-run verified: ${candidates.length} references, ${orphanCount} orphans.`,
    );
    console.log(`Fingerprint: ${fingerprint}`);
    console.log(`Receipt: ${receipt.path}`);
    console.log(`Receipt SHA-256: ${receipt.hash}`);
    return;
  }

  if (options.expectedFingerprint !== fingerprint) {
    throw new Error("preflight_fingerprint_changed");
  }

  let finalized = 0;
  for (const candidate of candidates) {
    const oldPath = candidatePath.get(candidate.message_id)!;
    const audit = audits.get(oldPath)!;
    const contract = candidateContract(candidate, oldPath, audit);
    const attachmentId = await deterministicAttachmentId(
      candidate.message_id,
      oldPath,
    );
    const privatePath =
      `${candidate.tenant_id}/${candidate.conversation_id}/${attachmentId}.${contract.extension}`;
    const source = await downloadObject(PUBLIC_BUCKET, oldPath);
    if (
      source.bytes.byteLength !== audit.sizeBytes ||
      await sha256Hex(source.bytes) !== audit.sha256
    ) {
      throw new Error("public_object_changed_after_preflight");
    }

    await uploadPrivateObject(
      PRIVATE_BUCKET,
      privatePath,
      source.bytes,
      contract.contentType,
    );
    const privateReadback = await downloadObject(PRIVATE_BUCKET, privatePath);
    if (
      privateReadback.bytes.byteLength !== audit.sizeBytes ||
      await sha256Hex(privateReadback.bytes) !== audit.sha256
    ) {
      throw new Error("private_copy_readback_mismatch");
    }

    await rpc("finalize_legacy_messaging_attachment_backfill", {
      p_message_id: candidate.message_id,
      p_attachment_id: attachmentId,
      p_storage_path: privatePath,
      p_original_filename: contract.filename,
      p_extension: contract.extension,
      p_declared_mime_type: contract.contentType,
      p_size_bytes: audit.sizeBytes,
      p_sha256: audit.sha256,
      p_expected_legacy_url: candidate.legacy_url,
    });

    const registryRows = await restRows<JsonRecord>(
      `messaging_attachments?select=id,message_id,storage_bucket,storage_path,size_bytes,sha256,status&id=eq.${attachmentId}`,
    );
    const messageRows = await restRows<JsonRecord>(
      `messages?select=id,content,metadata&id=eq.${candidate.message_id}`,
    );
    const registry = registryRows[0];
    const message = messageRows[0];
    const metadata = (message?.metadata ?? {}) as JsonRecord;
    const forbiddenKeys = [
      "url",
      "media_url",
      "image_url",
      "file_url",
      "documentUrl",
      "document_url",
      "storage_url",
      "public_url",
      "whatsapp_media_url",
      "download_url",
    ];
    if (
      registryRows.length !== 1 ||
      messageRows.length !== 1 ||
      registry.storage_bucket !== PRIVATE_BUCKET ||
      registry.storage_path !== privatePath ||
      registry.sha256 !== audit.sha256 ||
      registry.status !== "attached" ||
      metadata.attachment_id !== attachmentId ||
      metadata.storage_bucket !== PRIVATE_BUCKET ||
      metadata.storage_path !== privatePath ||
      forbiddenKeys.some((key) => key in metadata) ||
      message.content === candidate.legacy_url
    ) {
      throw new Error("database_readback_mismatch");
    }
    finalized += 1;
  }

  // No public deletion begins until every referenced message has an atomic
  // registry+metadata receipt. Refresh candidates to catch concurrent legacy
  // writes and fail closed before deleting anything they could reference.
  const candidatesAfterFinalize = await rpc<LegacyCandidate[]>(
    "list_legacy_messaging_attachment_candidates",
  );
  if (candidatesAfterFinalize.length !== 0) {
    throw new Error("legacy_references_remain_before_delete");
  }

  // A missing current message reference is not proof that an object has no
  // business value. Preserve every orphan byte-for-byte in a private bucket
  // before any public deletion. The quarantine path and durable DB receipt use
  // hashes only, so neither leaks the old public path, filename or customer.
  const orphanAudits = Array.from(audits.values()).filter((audit) => audit.referenceCount === 0);
  let quarantinedOrphans = 0;
  const orphanSourcePathHashes = new Map<string, string>();
  for (const audit of orphanAudits) {
    const current = await downloadObject(PUBLIC_BUCKET, audit.path);
    if (
      current.bytes.byteLength !== audit.sizeBytes ||
      await sha256Hex(current.bytes) !== audit.sha256
    ) {
      throw new Error("orphan_changed_before_quarantine");
    }

    const sourcePathHash = await sha256Hex(
      `vinabike-public-orphan-path-v1:${audit.path}`,
    );
    const quarantinePath = `legacy-orphans/${audit.sha256}`;
    const quarantineContentType = audit.contentType ||
      "application/octet-stream";
    await uploadPrivateObject(
      QUARANTINE_BUCKET,
      quarantinePath,
      current.bytes,
      quarantineContentType,
    );
    const quarantineReadback = await downloadObject(
      QUARANTINE_BUCKET,
      quarantinePath,
    );
    if (
      quarantineReadback.bytes.byteLength !== audit.sizeBytes ||
      await sha256Hex(quarantineReadback.bytes) !== audit.sha256
    ) {
      throw new Error("orphan_quarantine_readback_mismatch");
    }

    await rpc("finalize_legacy_messaging_orphan_quarantine", {
      p_source_path_sha256: sourcePathHash,
      p_source_content_sha256: audit.sha256,
      p_size_bytes: audit.sizeBytes,
      p_source_created_at: audit.createdAt.toISOString(),
    });
    const quarantineReceipts = await restRows<JsonRecord>(
      `messaging_legacy_orphan_quarantine_receipts?select=source_path_sha256,source_content_sha256,quarantine_bucket,quarantine_path,size_bytes,deleted_from_public_at&source_path_sha256=eq.${sourcePathHash}`,
    );
    const quarantineReceipt = quarantineReceipts[0];
    if (
      quarantineReceipts.length !== 1 ||
      quarantineReceipt.source_content_sha256 !== audit.sha256 ||
      quarantineReceipt.quarantine_bucket !== QUARANTINE_BUCKET ||
      quarantineReceipt.quarantine_path !== quarantinePath ||
      Number(quarantineReceipt.size_bytes) !== audit.sizeBytes
    ) {
      throw new Error("orphan_quarantine_receipt_readback_mismatch");
    }
    orphanSourcePathHashes.set(audit.path, sourcePathHash);
    quarantinedOrphans += 1;
  }

  const ageCutoff = Date.now() - options.minOrphanAgeHours * 60 * 60 * 1000;
  const deletable = Array.from(audits.values()).filter((audit) =>
    audit.createdAt.getTime() <= ageCutoff
  );
  const skippedYoungOrphans =
    orphanAudits.filter((audit) => audit.createdAt.getTime() > ageCutoff).length;
  if (deletable.length > 0) {
    // Re-download immediately before deletion and compare the preflight hash.
    for (const audit of deletable) {
      const current = await downloadObject(PUBLIC_BUCKET, audit.path);
      if (
        current.bytes.byteLength !== audit.sizeBytes ||
        await sha256Hex(current.bytes) !== audit.sha256
      ) {
        throw new Error("public_object_changed_before_delete");
      }
    }
    try {
      await deletePublicObjects(deletable.map((audit) => audit.path));
    } catch (_) {
      // Storage may commit a delete and lose its HTTP acknowledgement. Resolve
      // that ambiguity by authoritative enumeration before deciding to retry.
    }
    const objectsAfterDelete = await rpc<LegacyObject[]>(
      "list_legacy_messaging_public_objects",
    );
    const remainingAfterDelete = new Set(
      objectsAfterDelete.map((object) => object.storage_path),
    );
    for (const audit of deletable) {
      if (remainingAfterDelete.has(audit.path)) continue;
      if (audit.referenceCount !== 0) continue;
      const sourcePathHash = orphanSourcePathHashes.get(audit.path);
      if (!sourcePathHash) {
        throw new Error("orphan_delete_without_quarantine_receipt");
      }
      try {
        await rpc("mark_legacy_messaging_orphan_public_deleted", {
          p_source_path_sha256: sourcePathHash,
          p_source_content_sha256: audit.sha256,
        });
      } catch (_) {
        const receipts = await restRows<JsonRecord>(
          `messaging_legacy_orphan_quarantine_receipts?select=deleted_from_public_at&source_path_sha256=eq.${sourcePathHash}`,
        );
        if (
          receipts.length !== 1 ||
          typeof receipts[0].deleted_from_public_at !== "string"
        ) {
          throw new Error("orphan_delete_receipt_outcome_unknown");
        }
      }
    }
    if (deletable.some((audit) => remainingAfterDelete.has(audit.path))) {
      throw new Error("public_delete_incomplete");
    }
  }

  const finalCandidates = await rpc<LegacyCandidate[]>(
    "list_legacy_messaging_attachment_candidates",
  );
  const finalObjects = await rpc<LegacyObject[]>(
    "list_legacy_messaging_public_objects",
  );
  const deletedPaths = new Set(deletable.map((audit) => audit.path));
  if (
    finalCandidates.length !== 0 ||
    finalObjects.some((object) => deletedPaths.has(object.storage_path))
  ) {
    throw new Error("final_public_cleanup_readback_failed");
  }

  let deletedOrphanReceipts = 0;
  for (const audit of deletable) {
    if (audit.referenceCount !== 0) continue;
    const sourcePathHash = orphanSourcePathHashes.get(audit.path);
    if (!sourcePathHash) {
      throw new Error("deleted_orphan_missing_source_hash");
    }
    const receipts = await restRows<JsonRecord>(
      `messaging_legacy_orphan_quarantine_receipts?select=deleted_from_public_at&source_path_sha256=eq.${sourcePathHash}`,
    );
    if (
      receipts.length !== 1 ||
      typeof receipts[0].deleted_from_public_at !== "string"
    ) {
      throw new Error("deleted_orphan_receipt_readback_mismatch");
    }
    deletedOrphanReceipts += 1;
  }

  const receipt = await writeReceipt({
    receipt_version: 2,
    project_ref: PROJECT_REF,
    mode: "execute",
    status: "verified",
    started_at: startedAt.toISOString(),
    completed_at: new Date().toISOString(),
    preflight,
    result: {
      finalized_private_attachments: finalized,
      quarantined_orphan_objects: quarantinedOrphans,
      deleted_public_objects: deletable.length,
      deleted_orphan_objects_with_private_receipt: deletedOrphanReceipts,
      skipped_young_orphans: skippedYoungOrphans,
      remaining_public_scope_objects: finalObjects.length,
      remaining_legacy_references: finalCandidates.length,
    },
    contains_paths_or_pii: false,
  });
  console.log(
    `Execution verified: ${finalized} references privatized, ${deletable.length} public objects deleted.`,
  );
  console.log(`Receipt: ${receipt.path}`);
  console.log(`Receipt SHA-256: ${receipt.hash}`);
}

try {
  await main();
} catch (error) {
  const rawCode = error instanceof Error ? error.message : "unknown_failure";
  const code = rawCode.replace(/[^a-zA-Z0-9_.-]/g, "_").slice(0, 160);
  const receipt = await writeReceipt({
    receipt_version: 2,
    project_ref: PROJECT_REF,
    mode: options.execute ? "execute" : "dry-run",
    status: "failed",
    completed_at: new Date().toISOString(),
    failure_code: code,
    contains_paths_or_pii: false,
  });
  console.error(`Backfill stopped safely: ${code}`);
  console.error(`Failure receipt: ${receipt.path}`);
  console.error(`Receipt SHA-256: ${receipt.hash}`);
  Deno.exit(1);
}
