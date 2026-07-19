import { JsonRecord, TransactionalTemplateKey } from "./types.ts";

export type AttachmentDeliveryPolicy = "none" | "link_only";

export class AttachmentManifestError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AttachmentManifestError";
  }
}

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function secureHttpsUrl(value: unknown): string | null {
  const candidate = text(value);
  if (!candidate || candidate.length > 2048) return null;
  try {
    const url = new URL(candidate);
    if (
      url.protocol !== "https:" || !url.hostname || url.username ||
      url.password || url.hash
    ) {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

/**
 * Official artifacts are currently delivered as HTTPS CTAs, never fetched by
 * the worker and never attached as untrusted bytes. The immutable manifest is
 * retained as evidence and must match the renderer's official payload.
 */
export function validateAttachmentDeliveryPolicy(
  templateKey: TransactionalTemplateKey,
  manifest: unknown,
  payload: JsonRecord,
): AttachmentDeliveryPolicy {
  if (!Array.isArray(manifest)) {
    throw new AttachmentManifestError("Attachment manifest must be an array");
  }

  const officialShape = templateKey === "payment_voucher_available"
    ? {
      kind: "payment_voucher",
      evidence: record(payload.officialPaymentVoucher),
    }
    : templateKey === "tax_document_issued"
    ? {
      kind: "tax_document",
      evidence: record(payload.officialTaxDocument),
    }
    : null;

  if (!officialShape) {
    if (manifest.length !== 0) {
      throw new AttachmentManifestError(
        "Only official voucher or tax-document templates may carry artifacts",
      );
    }
    return "none";
  }

  if (manifest.length !== 1) {
    throw new AttachmentManifestError(
      "Official document email requires exactly one immutable artifact",
    );
  }

  const artifact = record(manifest[0]);
  const kind = text(artifact.kind);
  const url = secureHttpsUrl(artifact.url);
  const payloadUrl = secureHttpsUrl(officialShape.evidence.downloadUrl);
  const sha256 = text(artifact.sha256);
  const payloadSha256 = text(officialShape.evidence.artifactSha256);
  const mimeType = text(artifact.mimeType).toLowerCase();
  const providerDocumentId = text(artifact.providerDocumentId);
  const payloadProviderDocumentId = text(
    officialShape.evidence.providerDocumentId,
  );
  const issuedAt = text(artifact.issuedAt);
  const payloadIssuedAt = text(officialShape.evidence.issuedAt);

  if (kind !== officialShape.kind) {
    throw new AttachmentManifestError("Official artifact kind mismatch");
  }
  if (!url || !payloadUrl || url !== payloadUrl) {
    throw new AttachmentManifestError("Official artifact URL is unsafe or mismatched");
  }
  if (
    !/^[0-9a-f]{64}$/.test(sha256) || sha256 !== payloadSha256
  ) {
    throw new AttachmentManifestError("Official artifact hash is invalid or mismatched");
  }
  if (!["application/pdf", "application/xml", "text/xml"].includes(mimeType)) {
    throw new AttachmentManifestError("Official artifact MIME type is not allowed");
  }
  if (
    !providerDocumentId || providerDocumentId.length > 256 ||
    providerDocumentId !== payloadProviderDocumentId
  ) {
    throw new AttachmentManifestError(
      "Official provider document id is invalid or mismatched",
    );
  }
  if (
    !issuedAt || Number.isNaN(Date.parse(issuedAt)) ||
    issuedAt !== payloadIssuedAt
  ) {
    throw new AttachmentManifestError(
      "Official artifact issue time is invalid or mismatched",
    );
  }

  return "link_only";
}
