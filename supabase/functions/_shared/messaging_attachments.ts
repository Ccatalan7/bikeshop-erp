export const PRIVATE_MESSAGING_BUCKET = "chat-attachments";
export const MESSAGING_ATTACHMENT_SIGNED_URL_TTL_SECONDS = 300;
export const MAX_MESSAGING_ATTACHMENTS_PER_BATCH = 8;

const MIB = 1024 * 1024;

export const MESSAGING_ATTACHMENT_MIME_BY_EXTENSION: Readonly<Record<string, string>> = {
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

export interface MessagingAttachmentContract {
  extension: string;
  contentType: string;
  maxBytes: number;
}

export interface MessagingAttachmentReference {
  [key: string]: unknown;
  attachment_id: string;
  storage_bucket: typeof PRIVATE_MESSAGING_BUCKET;
  storage_path: string;
  filename: string;
  extension: string;
  content_type: string;
  size_bytes: number;
  attachment_access: "private_signed_runtime";
}

export function normalizedContentType(value: unknown) {
  if (typeof value !== "string") return "";
  return value.split(";")[0].trim().toLowerCase();
}

export function extensionForFilename(fileName: string) {
  const basename = fileName.trim().split(/[\\/]/).pop() ?? "";
  const dot = basename.lastIndexOf(".");
  if (dot <= 0 || dot === basename.length - 1) return "";
  return basename.slice(dot + 1).toLowerCase();
}

export function maxBytesForContentType(contentType: string) {
  if (contentType.startsWith("image/")) return 5 * MIB;
  if (contentType.startsWith("audio/") || contentType.startsWith("video/")) {
    return 16 * MIB;
  }
  if (contentType === "text/plain") return 2 * MIB;
  return 20 * MIB;
}

export function validateMessagingAttachment(params: {
  filename: string;
  contentType: string;
  sizeBytes: number;
}): MessagingAttachmentContract {
  const extension = extensionForFilename(params.filename);
  const expectedContentType = MESSAGING_ATTACHMENT_MIME_BY_EXTENSION[extension];
  const contentType = normalizedContentType(params.contentType);

  if (!expectedContentType || contentType !== expectedContentType) {
    throw new Error("unsupported_attachment_type");
  }

  if (!Number.isSafeInteger(params.sizeBytes) || params.sizeBytes <= 0) {
    throw new Error("invalid_attachment_size");
  }

  const maxBytes = maxBytesForContentType(contentType);
  if (params.sizeBytes > maxBytes) {
    throw new Error("attachment_too_large");
  }

  return { extension, contentType, maxBytes };
}

export function buildPrivateMessagingAttachmentPath(params: {
  tenantId: string;
  conversationId: string;
  attachmentId: string;
  extension: string;
}) {
  const uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
  const uuidPattern = new RegExp(`^${uuid}$`, "i");
  if (
    !uuidPattern.test(params.tenantId) ||
    !uuidPattern.test(params.conversationId) ||
    !uuidPattern.test(params.attachmentId)
  ) {
    throw new Error("invalid_attachment_path_identity");
  }

  const extension = params.extension.toLowerCase();
  if (!MESSAGING_ATTACHMENT_MIME_BY_EXTENSION[extension]) {
    throw new Error("unsupported_attachment_type");
  }

  return `${params.tenantId}/${params.conversationId}/${params.attachmentId}.${extension}`;
}

export function attachmentReference(params: {
  attachmentId: string;
  storagePath: string;
  filename: string;
  extension: string;
  contentType: string;
  sizeBytes: number;
}): MessagingAttachmentReference {
  return {
    attachment_id: params.attachmentId,
    storage_bucket: PRIVATE_MESSAGING_BUCKET,
    storage_path: params.storagePath,
    filename: params.filename,
    extension: params.extension,
    content_type: params.contentType,
    size_bytes: params.sizeBytes,
    attachment_access: "private_signed_runtime",
  };
}

export function isCanonicalPrivateAttachmentPath(params: {
  path: string;
  tenantId: string;
  conversationId: string;
  attachmentId: string;
  extension: string;
}) {
  try {
    return params.path === buildPrivateMessagingAttachmentPath({
      tenantId: params.tenantId,
      conversationId: params.conversationId,
      attachmentId: params.attachmentId,
      extension: params.extension,
    });
  } catch (_) {
    return false;
  }
}

/**
 * Dual-read only for objects created before the private attachment contract.
 * It intentionally accepts no third-party host and no arbitrary bucket/path.
 */
export function isTrustedLegacyMessagingUrl(
  value: unknown,
  supabaseUrl: string,
) {
  if (typeof value !== "string") return false;
  try {
    const candidate = new URL(value);
    const expected = new URL(supabaseUrl);
    if (!["https:", "http:"].includes(candidate.protocol)) return false;
    if (candidate.host !== expected.host) return false;
    const prefix = "/storage/v1/object/public/vinabike-assets/";
    if (!candidate.pathname.startsWith(prefix)) return false;
    const relative = candidate.pathname.slice(prefix.length);
    return relative.startsWith("chat/") || relative.startsWith("whatsapp-media/");
  } catch (_) {
    return false;
  }
}

export function stringValue(value: unknown) {
  if (typeof value !== "string") return undefined;
  const text = value.trim();
  return text.length > 0 ? text : undefined;
}
